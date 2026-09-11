// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Compares the two parsed surfaces and classifies every member.
///
/// The comparison normalizes both type languages into a small shared
/// vocabulary and compares named object types structurally, not by
/// name. What the normalization cannot carry is classified
/// `undecidable` with a reason -- never forced into `different`.
library;

import 'source_text.dart';
import 'surface_model.dart';

/// How one member compares across the two sides.
enum SurfaceClassification {
  /// Present only in the Chrome source.
  chromeOnly,

  /// Present only in the Firefox source.
  firefoxOnly,

  /// Present on both sides with an equivalent signature.
  sameSignature,

  /// Present on both sides with signatures known to differ.
  differentSignature,

  /// Present on both sides, but the comparison cannot decide.
  undecidable,
}

/// One line of the report: a member and its classification.
class ComparisonRow {
  /// Creates a row.
  const ComparisonRow({
    required this.namespace,
    required this.memberName,
    required this.memberKind,
    required this.classification,
    required this.note,
  });

  /// The namespace in API notation.
  final String namespace;

  /// The member name.
  final String memberName;

  /// `function` or `event`.
  final String memberKind;

  /// The verdict.
  final SurfaceClassification classification;

  /// The reason behind a `different` or `undecidable` verdict, empty
  /// otherwise.
  final String note;
}

/// Compares [chrome] against [firefox] for the given [namespaces]
/// (API notation) and returns one row per function and event, sorted
/// by namespace order, then member name, then kind.
List<ComparisonRow> compareSurfaces({
  required SurfaceCatalog chrome,
  required SurfaceCatalog firefox,
  required List<String> namespaces,
}) {
  final comparison = _Comparison(chrome, firefox);
  final rows = <ComparisonRow>[];
  for (final name in namespaces) {
    final chromeSurface = chrome.namespace(name);
    final firefoxSurface = firefox.namespace(name);
    if (chromeSurface == null || firefoxSurface == null) {
      throw ArgumentError('namespace $name missing from a parsed catalog');
    }
    rows.addAll(comparison.compareNamespace(chromeSurface, firefoxSurface));
  }
  return rows;
}

/// A verdict about one type or signature aspect.
class _Verdict {
  const _Verdict._(this.rank, this.reason);

  const _Verdict.same() : this._(0, '');

  const _Verdict.undecidable(String reason) : this._(1, reason);

  const _Verdict.different(String reason) : this._(2, reason);

  /// 0 same, 1 undecidable, 2 different. A known difference outranks
  /// an open question: once one aspect provably differs, the member
  /// differs, whatever else is unclear.
  final int rank;
  final String reason;

  _Verdict merge(_Verdict other) {
    if (other.rank == 0) {
      return this;
    }
    if (rank == 0) {
      return other;
    }
    if (rank == other.rank) {
      return _Verdict._(rank, _joinReasons(reason, other.reason));
    }
    return rank > other.rank ? this : other;
  }

  static String _joinReasons(String a, String b) {
    if (a.isEmpty) {
      return b;
    }
    if (b.isEmpty || a.contains(b)) {
      return a;
    }
    return '$a; $b';
  }
}

/// The parsed shape of one raw type expression.
class _ParsedType {
  const _ParsedType(this.kind,
      {this.inner, this.name, this.values, this.raw, this.nullable = false});

  final _TypeKind kind;
  final _ParsedType? inner;
  final String? name;
  final Set<String>? values;
  final String? raw;

  /// Whether the expression allows the absent value (`T?` on the Dart
  /// side, `T | undefined` or `T | null` on the TypeScript side).
  final bool nullable;

  _ParsedType asNullable() => _ParsedType(kind,
      inner: inner, name: name, values: values, raw: raw, nullable: true);
}

enum _TypeKind {
  voidType,
  boolType,
  numberType,
  stringType,
  anyType,
  binaryType,
  listType,
  promiseType,
  namedType,
  inlineEnumType,
  functionType,
  eventType,
  unionType,
  unknownShape,
}

class _Comparison {
  _Comparison(this.chrome, this.firefox);

  final SurfaceCatalog chrome;
  final SurfaceCatalog firefox;

  /// Dictionary pairs currently being compared, to cut cycles: a pair
  /// met again while still open is taken as consistent.
  final _openPairs = <String>{};

  static const _maximumDepth = 6;

  List<ComparisonRow> compareNamespace(
      NamespaceSurface chromeSurface, NamespaceSurface firefoxSurface) {
    final rows = <ComparisonRow>[];

    final chromeFunctions = {
      for (final function in chromeSurface.functions) function.name: function,
    };
    final firefoxFunctions = {
      for (final function in firefoxSurface.functions) function.name: function,
    };
    final functionNames = <String>{
      ...chromeFunctions.keys,
      ...firefoxFunctions.keys,
    }.toList()
      ..sort();
    for (final name in functionNames) {
      rows.add(_functionRow(chromeSurface.namespace, name,
          chromeFunctions[name], firefoxFunctions[name]));
    }

    final chromeEvents = {
      for (final event in chromeSurface.events) event.name: event,
    };
    final firefoxEvents = {
      for (final event in firefoxSurface.events) event.name: event,
    };
    final eventNames = <String>{
      ...chromeEvents.keys,
      ...firefoxEvents.keys,
    }.toList()
      ..sort();
    for (final name in eventNames) {
      rows.add(_eventRow(chromeSurface.namespace, name, chromeEvents[name],
          firefoxEvents[name]));
    }

    rows.sort((a, b) {
      final byName = a.memberName.compareTo(b.memberName);
      if (byName != 0) {
        return byName;
      }
      return a.memberKind.compareTo(b.memberKind);
    });
    return rows;
  }

  ComparisonRow _functionRow(String namespace, String name,
      FunctionMember? chromeFunction, FunctionMember? firefoxFunction) {
    if (chromeFunction == null) {
      return _row(
          namespace, name, 'function', SurfaceClassification.firefoxOnly, '');
    }
    if (firefoxFunction == null) {
      return _row(
          namespace, name, 'function', SurfaceClassification.chromeOnly, '');
    }
    final folded = _foldOverloads(firefoxFunction.overloads);
    if (folded == null) {
      return _row(
          namespace,
          name,
          'function',
          SurfaceClassification.undecidable,
          'firefox overloads do not fold into one optional-parameter '
              'signature');
    }
    final chromeSignature = chromeFunction.overloads.single;
    final verdict = _compareSignatures(chromeSignature, folded);
    return _rowFromVerdict(namespace, name, 'function', verdict);
  }

  ComparisonRow _eventRow(String namespace, String name,
      EventMember? chromeEvent, EventMember? firefoxEvent) {
    if (chromeEvent == null) {
      return _row(
          namespace, name, 'event', SurfaceClassification.firefoxOnly, '');
    }
    if (firefoxEvent == null) {
      return _row(
          namespace, name, 'event', SurfaceClassification.chromeOnly, '');
    }
    var firefoxCallback = firefoxEvent.callbackParameters;
    final unresolved = firefoxEvent.unresolvedCallbackType;
    if (unresolved != null) {
      final resolved = _resolveNamedCallback(unresolved);
      if (resolved == null) {
        return _row(
            namespace,
            name,
            'event',
            SurfaceClassification.undecidable,
            'firefox listener type $unresolved does not resolve to one '
                'callback signature');
      }
      firefoxCallback = resolved;
    }
    var verdict =
        _compareEventPayload(chromeEvent.callbackParameters, firefoxCallback);
    if (firefoxEvent.registrationParameters.isNotEmpty) {
      final extras = firefoxEvent.registrationParameters
          .map((parameter) => parameter.name)
          .join(', ');
      verdict = verdict.merge(_Verdict.different(
          'firefox listener registration additionally takes ($extras); '
          'the chrome source takes only the callback'));
    }
    return _rowFromVerdict(namespace, name, 'event', verdict);
  }

  ComparisonRow _rowFromVerdict(
      String namespace, String name, String kind, _Verdict verdict) {
    final classification = switch (verdict.rank) {
      0 => SurfaceClassification.sameSignature,
      1 => SurfaceClassification.undecidable,
      _ => SurfaceClassification.differentSignature,
    };
    return _row(namespace, name, kind, classification, verdict.reason);
  }

  ComparisonRow _row(String namespace, String name, String kind,
          SurfaceClassification classification, String note) =>
      ComparisonRow(
        namespace: namespace,
        memberName: name,
        memberKind: kind,
        classification: classification,
        note: note,
      );

  /// Folds several overloads into one signature whose omittable
  /// parameters are optional. Returns null when the overloads do not
  /// have that shape.
  FunctionSignature? _foldOverloads(List<FunctionSignature> overloads) {
    if (overloads.length == 1) {
      return overloads.single;
    }
    var base = overloads.first;
    for (final signature in overloads) {
      if (signature.parameters.length > base.parameters.length) {
        base = signature;
      }
    }
    final optionalNames = <String>{
      for (final parameter in base.parameters)
        if (parameter.optional) parameter.name,
    };
    for (final signature in overloads) {
      if (signature.returnType != base.returnType) {
        return null;
      }
      if (identical(signature, base)) {
        continue;
      }
      // Every shorter overload must be the base with some parameters
      // left out, order preserved.
      var baseIndex = 0;
      for (final parameter in signature.parameters) {
        var found = false;
        while (baseIndex < base.parameters.length) {
          final candidate = base.parameters[baseIndex];
          baseIndex++;
          if (candidate.name == parameter.name &&
              candidate.type == parameter.type) {
            found = true;
            break;
          }
          optionalNames.add(candidate.name);
        }
        if (!found) {
          return null;
        }
      }
      for (var i = baseIndex; i < base.parameters.length; i++) {
        optionalNames.add(base.parameters[i].name);
      }
    }
    return FunctionSignature([
      for (final parameter in base.parameters)
        ParameterSpec(parameter.name, parameter.type,
            optional:
                parameter.optional || optionalNames.contains(parameter.name)),
    ], base.returnType);
  }

  _Verdict _compareSignatures(
      FunctionSignature chromeSignature, FunctionSignature firefoxSignature) {
    var verdict = const _Verdict.same();
    if (chromeSignature.parameters.length !=
        firefoxSignature.parameters.length) {
      return _Verdict.different('parameter count differs: chrome takes '
          '${chromeSignature.parameters.length} '
          '(${_parameterNames(chromeSignature.parameters)}), firefox takes '
          '${firefoxSignature.parameters.length} '
          '(${_parameterNames(firefoxSignature.parameters)})');
    }
    for (var i = 0; i < chromeSignature.parameters.length; i++) {
      final chromeParameter = chromeSignature.parameters[i];
      final firefoxParameter = firefoxSignature.parameters[i];
      if (chromeParameter.optional != firefoxParameter.optional) {
        verdict = verdict
            .merge(_Verdict.different('parameter ${chromeParameter.name} is '
                '${chromeParameter.optional ? 'optional' : 'required'} on the '
                'chrome side and '
                '${firefoxParameter.optional ? 'optional' : 'required'} on the '
                'firefox side'));
      }
      verdict = verdict.merge(_labeled('parameter ${chromeParameter.name}',
          _compareTypes(chromeParameter.type, firefoxParameter.type, 0)));
    }
    return verdict.merge(_labeled(
        'return type',
        _compareReturnTypes(
            chromeSignature.returnType, firefoxSignature.returnType)));
  }

  String _parameterNames(List<ParameterSpec> parameters) => parameters.isEmpty
      ? 'nothing'
      : parameters.map((parameter) => parameter.name).join(', ');

  _Verdict _labeled(String label, _Verdict verdict) {
    if (verdict.rank == 0 || verdict.reason.isEmpty) {
      return verdict;
    }
    return _Verdict._(verdict.rank, '$label: ${verdict.reason}');
  }

  /// Return types compare like any type; the promise-mismatch branch of
  /// [_compareParsed] is what reports a sync-vs-async difference.
  _Verdict _compareReturnTypes(String chromeType, String firefoxType) =>
      _compareTypes(chromeType, firefoxType, 0);

  _Verdict _compareEventPayload(List<ParameterSpec> chromeParameters,
      List<ParameterSpec> firefoxParameters) {
    if (chromeParameters.isEmpty) {
      if (firefoxParameters.isEmpty) {
        return const _Verdict.same();
      }
      return _Verdict.different(
          'chrome callback takes nothing, firefox callback takes '
          '(${_parameterNames(firefoxParameters)})');
    }
    final chromePayload = chromeParameters.single.type;
    if (firefoxParameters.isEmpty) {
      return _Verdict.different(
          'chrome callback carries $chromePayload, firefox callback takes '
          'nothing');
    }
    if (firefoxParameters.length == 1) {
      return _labeled('callback parameter',
          _compareTypes(chromePayload, firefoxParameters.single.type, 0));
    }
    // Several firefox callback parameters: the Dart generator wraps
    // them into one synthesized class whose fields mirror them in
    // order.
    final chromeDictionary = chrome.dictionary(chromePayload);
    if (chromeDictionary == null) {
      return _Verdict.undecidable(
          'firefox callback takes ${firefoxParameters.length} parameters, '
          'chrome payload $chromePayload is not a resolvable wrapper class');
    }
    if (chromeDictionary.fields.length != firefoxParameters.length) {
      return _Verdict.different(
          'callback parameter count differs: chrome wrapper '
          '$chromePayload carries ${chromeDictionary.fields.length} fields '
          '(${chromeDictionary.fields.map((field) => field.name).join(', ')}), '
          'firefox callback takes ${firefoxParameters.length} '
          '(${_parameterNames(firefoxParameters)})');
    }
    var verdict = const _Verdict.same();
    for (var i = 0; i < firefoxParameters.length; i++) {
      verdict = verdict.merge(_labeled(
          'callback parameter ${firefoxParameters[i].name}',
          _compareTypes(
              chromeDictionary.fields[i].type, firefoxParameters[i].type, 1)));
    }
    return verdict;
  }

  _Verdict _compareTypes(String chromeRaw, String firefoxRaw, int depth) =>
      _compareParsed(
          _parseChromeType(chromeRaw), _parseFirefoxType(firefoxRaw), depth);

  _Verdict _compareParsed(
      _ParsedType chromeType, _ParsedType firefoxType, int depth) {
    if (depth > _maximumDepth) {
      return const _Verdict.undecidable(
          'nesting deeper than the comparison follows');
    }
    var verdict = const _Verdict.same();
    if (chromeType.nullable != firefoxType.nullable) {
      verdict = _Verdict.different('nullability differs: '
          '${chromeType.raw} vs ${firefoxType.raw}');
    }
    final inner = _compareParsedCore(chromeType, firefoxType, depth);
    return verdict.merge(inner);
  }

  _Verdict _compareParsedCore(
      _ParsedType chromeType, _ParsedType firefoxType, int depth) {
    // Unions that are not just `| undefined` cannot be mirrored by the
    // Dart side's type system as generated; do not guess.
    if (firefoxType.kind == _TypeKind.unionType) {
      return _Verdict.undecidable(
          'firefox side is a union type (${firefoxType.raw}) with no '
          'generated Dart counterpart shape');
    }
    if (chromeType.kind == _TypeKind.unknownShape ||
        firefoxType.kind == _TypeKind.unknownShape) {
      final sides = <String>[
        if (chromeType.kind == _TypeKind.unknownShape)
          'chrome side ${chromeType.raw}',
        if (firefoxType.kind == _TypeKind.unknownShape)
          'firefox side ${firefoxType.raw}',
      ];
      return _Verdict.undecidable(
          'unhandled type shape on the ${sides.join(' and the ')}');
    }
    if (chromeType.kind == _TypeKind.anyType ||
        firefoxType.kind == _TypeKind.anyType) {
      if (chromeType.kind == firefoxType.kind) {
        return const _Verdict.same();
      }
      final constrained =
          chromeType.kind == _TypeKind.anyType ? firefoxType : chromeType;
      return _Verdict.undecidable(
          'one side is unconstrained, the other declares '
          '${constrained.raw ?? constrained.name ?? constrained.kind.name}');
    }
    if (chromeType.kind == _TypeKind.eventType ||
        firefoxType.kind == _TypeKind.eventType) {
      if (chromeType.kind != firefoxType.kind) {
        return _Verdict.different(
            'event-valued on one side only (${chromeType.raw} vs '
            '${firefoxType.raw})');
      }
      final firefoxCallback = _tryCallbackParameters(firefoxType.raw ?? '');
      if (firefoxCallback == null) {
        return _Verdict.undecidable(
            'firefox event callback shape not parseable: '
            '${firefoxType.raw}');
      }
      final chromePayload = chromeType.inner!;
      return _compareEventPayload(
          chromePayload.kind == _TypeKind.voidType
              ? const []
              : [ParameterSpec('', chromePayload.raw ?? '')],
          firefoxCallback);
    }
    if (chromeType.kind == _TypeKind.functionType ||
        firefoxType.kind == _TypeKind.functionType) {
      if (chromeType.kind != firefoxType.kind) {
        return const _Verdict.different('function-valued on one side only');
      }
      return const _Verdict.undecidable(
          'function-typed values are not compared in depth');
    }
    if (chromeType.kind == _TypeKind.listType ||
        firefoxType.kind == _TypeKind.listType) {
      if (chromeType.kind != firefoxType.kind) {
        return _Verdict.different(
            'list on one side only (${chromeType.raw} vs ${firefoxType.raw})');
      }
      return _compareParsed(chromeType.inner!, firefoxType.inner!, depth + 1);
    }
    if (chromeType.kind == _TypeKind.promiseType ||
        firefoxType.kind == _TypeKind.promiseType) {
      if (chromeType.kind != firefoxType.kind) {
        return _Verdict.different('asynchrony differs: '
            '${chromeType.raw} vs ${firefoxType.raw}');
      }
      return _compareParsed(chromeType.inner!, firefoxType.inner!, depth + 1);
    }

    final chromePrimitive = _primitiveName(chromeType.kind);
    final firefoxPrimitive = _primitiveName(firefoxType.kind);
    if (chromePrimitive != null || firefoxPrimitive != null) {
      if (chromePrimitive == firefoxPrimitive) {
        return const _Verdict.same();
      }
      // A named type on one side against a primitive on the other can
      // still be an enum against its wire type -- that is a looseness
      // difference, reported as such below via name resolution.
      if (chromeType.kind == _TypeKind.namedType ||
          firefoxType.kind == _TypeKind.namedType ||
          chromeType.kind == _TypeKind.inlineEnumType ||
          firefoxType.kind == _TypeKind.inlineEnumType) {
        return _Verdict.different('a closed or named type on one side against '
            '${chromePrimitive ?? firefoxPrimitive} on the other '
            '(${chromeType.raw} vs ${firefoxType.raw})');
      }
      return _Verdict.different(
          'primitive types differ: ${chromeType.raw} vs ${firefoxType.raw}');
    }

    // Inline enums and named types remain.
    final chromeEnum = chromeType.kind == _TypeKind.inlineEnumType
        ? EnumDefinition('(inline)', chromeType.values!)
        : (chromeType.kind == _TypeKind.namedType
            ? chrome.enumDefinition(chromeType.name!)
            : null);
    final firefoxEnum = firefoxType.kind == _TypeKind.inlineEnumType
        ? EnumDefinition('(inline)', firefoxType.values!)
        : (firefoxType.kind == _TypeKind.namedType
            ? _resolveFirefoxEnum(firefoxType)
            : null);
    if (chromeEnum != null && firefoxEnum != null) {
      return _compareEnums(chromeEnum, firefoxEnum);
    }

    if (chromeType.kind == _TypeKind.namedType &&
        firefoxType.kind == _TypeKind.namedType) {
      return _compareNamed(chromeType, firefoxType, depth);
    }
    if ((chromeEnum != null) != (firefoxEnum != null)) {
      return _Verdict.different(
          'a closed value set on one side against an object type on the '
          'other (${chromeType.raw} vs ${firefoxType.raw})');
    }
    return _Verdict.undecidable('type shapes not comparable: '
        '${chromeType.raw} vs ${firefoxType.raw}');
  }

  String? _primitiveName(_TypeKind kind) => switch (kind) {
        _TypeKind.voidType => 'void',
        _TypeKind.boolType => 'boolean',
        _TypeKind.numberType => 'number',
        _TypeKind.stringType => 'string',
        _TypeKind.binaryType => 'binary',
        _ => null,
      };

  _Verdict _compareEnums(
      EnumDefinition chromeEnum, EnumDefinition firefoxEnum) {
    final onlyChrome = chromeEnum.values.difference(firefoxEnum.values);
    final onlyFirefox = firefoxEnum.values.difference(chromeEnum.values);
    if (onlyChrome.isEmpty && onlyFirefox.isEmpty) {
      return const _Verdict.same();
    }
    final parts = <String>[
      if (onlyChrome.isNotEmpty)
        'values only on the chrome side: ${_shortList(onlyChrome)}',
      if (onlyFirefox.isNotEmpty)
        'values only on the firefox side: ${_shortList(onlyFirefox)}',
    ];
    return _Verdict.different('enum ${chromeEnum.name} vs ${firefoxEnum.name}: '
        '${parts.join('; ')}');
  }

  EnumDefinition? _resolveFirefoxEnum(_ParsedType type) {
    final name = type.name!;
    if (name.contains('.')) {
      final parts = name.split('.');
      final surface = firefox.namespace(_lowerFirst(parts.first));
      return surface?.enums[parts.last];
    }
    return firefox.enumDefinition(name);
  }

  _Verdict _compareNamed(
      _ParsedType chromeType, _ParsedType firefoxType, int depth) {
    final chromeDictionary = chrome.dictionary(chromeType.name!);
    final firefoxDictionary = _resolveFirefoxDictionary(firefoxType.name!);
    if (firefoxDictionary == null) {
      final qualified = firefoxType.name!.contains('.');
      return _Verdict.undecidable(qualified
          ? 'firefox type ${firefoxType.name} is declared outside the '
              'compared namespaces'
          : 'firefox type ${firefoxType.name} not found in the parsed '
              'sources');
    }
    if (chromeDictionary == null) {
      // Not a dictionary; it could still be an enum matched against a
      // firefox dictionary, which is a plain difference. An unknown
      // name is undecidable.
      if (chrome.enumDefinition(chromeType.name!) != null) {
        return _Verdict.different(
            'chrome ${chromeType.name} is a closed value set, firefox '
            '${firefoxType.name} is an object type');
      }
      return _Verdict.undecidable(
          'chrome type ${chromeType.name} not found in the parsed sources');
    }
    final pairKey = '${chromeType.name}|${firefoxType.name}';
    if (_openPairs.contains(pairKey)) {
      return const _Verdict.same();
    }
    _openPairs.add(pairKey);
    try {
      return _compareDictionaries(chromeDictionary, firefoxDictionary, depth);
    } finally {
      _openPairs.remove(pairKey);
    }
  }

  Dictionary? _resolveFirefoxDictionary(String name) {
    if (name.contains('.')) {
      final parts = name.split('.');
      final surface = firefox.namespace(_lowerFirst(parts.first));
      return surface?.dictionaries[parts.last];
    }
    return firefox.dictionary(name);
  }

  String _lowerFirst(String text) => text[0].toLowerCase() + text.substring(1);

  _Verdict _compareDictionaries(
      Dictionary chromeDictionary, Dictionary firefoxDictionary, int depth) {
    final firefoxFields = <String, DictionaryField>{};
    final unresolvedBase =
        _collectFirefoxFields(firefoxDictionary, firefoxFields);
    if (unresolvedBase != null) {
      return _Verdict.undecidable(
          '${firefoxDictionary.name} extends $unresolvedBase, which is '
          'declared outside the compared namespaces');
    }
    final chromeFields = {
      for (final field in chromeDictionary.fields) field.name: field,
    };

    // The Dart generator exposes some upstream methods as fields of a
    // JavaScript function type (Port carries `disconnect` and
    // `postMessage` that way). A function-typed field on one side and
    // a method of the same name on the other are the same member seen
    // through two generator conventions; both are compared by name
    // only, like plain methods.
    final chromeMethods = {...chromeDictionary.methodNames};
    final firefoxMethods = {...firefoxDictionary.methodNames};
    for (final name in chromeFields.keys.toList()) {
      if (firefoxMethods.contains(name) &&
          _parseChromeType(chromeFields[name]!.type).kind ==
              _TypeKind.functionType) {
        chromeFields.remove(name);
        chromeMethods.add(name);
      }
    }
    for (final name in firefoxFields.keys.toList()) {
      if (chromeMethods.contains(name) &&
          _parseFirefoxType(firefoxFields[name]!.type).kind ==
              _TypeKind.functionType) {
        firefoxFields.remove(name);
        firefoxMethods.add(name);
      }
    }

    var verdict = const _Verdict.same();
    final onlyChrome =
        chromeFields.keys.toSet().difference(firefoxFields.keys.toSet());
    final onlyFirefox =
        firefoxFields.keys.toSet().difference(chromeFields.keys.toSet());
    if (onlyChrome.isNotEmpty || onlyFirefox.isNotEmpty) {
      final parts = <String>[
        if (onlyChrome.isNotEmpty)
          'fields only on the chrome side: ${_shortList(onlyChrome)}',
        if (onlyFirefox.isNotEmpty)
          'fields only on the firefox side: ${_shortList(onlyFirefox)}',
      ];
      verdict = verdict.merge(_Verdict.different(
          '${chromeDictionary.name} vs ${firefoxDictionary.name}: '
          '${parts.join('; ')}'));
    }
    for (final name in chromeFields.keys) {
      final firefoxField = firefoxFields[name];
      if (firefoxField == null) {
        continue;
      }
      final chromeField = chromeFields[name]!;
      if (chromeField.optional != firefoxField.optional) {
        verdict = verdict.merge(_Verdict.different(
            'field ${chromeDictionary.name}.$name optionality differs'));
      }
      verdict = verdict.merge(_labeled('field ${chromeDictionary.name}.$name',
          _compareTypes(chromeField.type, firefoxField.type, depth + 1)));
    }

    final onlyChromeMethods = chromeMethods.difference(firefoxMethods);
    final onlyFirefoxMethods = firefoxMethods.difference(chromeMethods);
    if (onlyChromeMethods.isNotEmpty || onlyFirefoxMethods.isNotEmpty) {
      final parts = <String>[
        if (onlyChromeMethods.isNotEmpty)
          'methods only on the chrome side: ${_shortList(onlyChromeMethods)}',
        if (onlyFirefoxMethods.isNotEmpty)
          'methods only on the firefox side: ${_shortList(onlyFirefoxMethods)}',
      ];
      verdict = verdict.merge(_Verdict.different(
          '${chromeDictionary.name} vs ${firefoxDictionary.name}: '
          '${parts.join('; ')}'));
    }
    if (firefoxDictionary.hasIndexSignature) {
      verdict = verdict.merge(_Verdict.undecidable(
          '${firefoxDictionary.name} has an index signature the chrome '
          'side cannot mirror'));
    }
    return verdict;
  }

  /// Collects [dictionary]'s own and inherited fields into [into].
  /// Returns the name of an unresolvable base, or null on success.
  String? _collectFirefoxFields(
      Dictionary dictionary, Map<String, DictionaryField> into) {
    for (final base in dictionary.extendedTypes) {
      final resolved = _resolveFirefoxDictionary(base);
      if (resolved == null) {
        return base;
      }
      final unresolved = _collectFirefoxFields(resolved, into);
      if (unresolved != null) {
        return unresolved;
      }
    }
    for (final field in dictionary.fields) {
      into[field.name] = field;
    }
    return null;
  }

  String _shortList(Set<String> values) {
    final sorted = values.toList()..sort();
    if (sorted.length <= 5) {
      return sorted.join(', ');
    }
    return '${sorted.take(5).join(', ')}, and ${sorted.length - 5} more';
  }

  /// Follows the firefox type-alias chain from a named listener type
  /// and returns its callback parameters, or null when the chain does
  /// not end in exactly one inline callback signature.
  List<ParameterSpec>? _resolveNamedCallback(String name) {
    var current = name.trim();
    for (var hops = 0; hops < 5; hops++) {
      if (current.startsWith('(')) {
        return _tryCallbackParameters(current);
      }
      final target = firefox.typeAlias(current);
      if (target == null) {
        return null;
      }
      current = target.trim();
    }
    return null;
  }

  List<ParameterSpec>? _tryCallbackParameters(String signature) {
    final match = RegExp(r'^\((.*)\) => .+$').firstMatch(signature.trim());
    if (match == null) {
      return null;
    }
    final parameters = <ParameterSpec>[];
    for (final part in splitTopLevel(match.group(1)!)) {
      final parameter = RegExp(r'^(\w+)(\?)?: (.+)$').firstMatch(part.trim());
      if (parameter == null) {
        return null;
      }
      parameters.add(ParameterSpec(parameter.group(1)!, parameter.group(3)!,
          optional: parameter.group(2) != null));
    }
    return parameters;
  }

  // ----- type expression parsing -----

  _ParsedType _parseChromeType(String raw) {
    final text = raw.trim();
    if (text.endsWith('?')) {
      return _parseChromeType(text.substring(0, text.length - 1)).asNullable();
    }
    final alias = chrome.typeAlias(text);
    if (alias != null) {
      return _parseChromeType(alias);
    }
    switch (text) {
      case 'void':
        return _ParsedType(_TypeKind.voidType, raw: text);
      case 'bool':
        return _ParsedType(_TypeKind.boolType, raw: text);
      case 'int':
      case 'double':
      case 'num':
        return _ParsedType(_TypeKind.numberType, raw: text);
      case 'String':
        return _ParsedType(_TypeKind.stringType, raw: text);
      case 'Object':
      case 'JSAny':
      case 'JSObject':
        return _ParsedType(_TypeKind.anyType, raw: text);
      case 'JSArrayBuffer':
        return _ParsedType(_TypeKind.binaryType, raw: text);
    }
    if (text == 'Map' || text.startsWith('Map<')) {
      return _ParsedType(_TypeKind.anyType, raw: text);
    }
    final future = _genericArgument(text, 'Future');
    if (future != null) {
      return _ParsedType(_TypeKind.promiseType,
          inner: _parseChromeType(future), raw: text);
    }
    final list = _genericArgument(text, 'List');
    if (list != null) {
      return _ParsedType(_TypeKind.listType,
          inner: _parseChromeType(list), raw: text);
    }
    final eventStream = _genericArgument(text, 'EventStream');
    if (eventStream != null) {
      return _ParsedType(_TypeKind.eventType,
          inner: _parseChromeType(eventStream), raw: text);
    }
    if (text.contains('Function')) {
      return _ParsedType(_TypeKind.functionType, raw: text);
    }
    if (RegExp(r'^\w+$').hasMatch(text)) {
      return _ParsedType(_TypeKind.namedType, name: text, raw: text);
    }
    return _ParsedType(_TypeKind.unknownShape, raw: text);
  }

  _ParsedType _parseFirefoxType(String raw) {
    final text = raw.trim();
    if (text.endsWith(' | undefined')) {
      return _parseFirefoxType(
              text.substring(0, text.length - ' | undefined'.length))
          .asNullable();
    }
    if (text.endsWith(' | null')) {
      return _parseFirefoxType(
              text.substring(0, text.length - ' | null'.length))
          .asNullable();
    }
    final aliasTarget = !text.contains('.') && !text.contains('<')
        ? firefox.typeAlias(text)
        : null;
    if (aliasTarget != null) {
      return _parseFirefoxType(aliasTarget);
    }
    switch (text) {
      case 'void':
        return _ParsedType(_TypeKind.voidType, raw: text);
      case 'boolean':
      case 'true':
      case 'false':
        return _ParsedType(_TypeKind.boolType, raw: text);
      case 'number':
        return _ParsedType(_TypeKind.numberType, raw: text);
      case 'string':
        return _ParsedType(_TypeKind.stringType, raw: text);
      case 'any':
      case 'unknown':
      case 'object':
        return _ParsedType(_TypeKind.anyType, raw: text);
      case 'ArrayBuffer':
        return _ParsedType(_TypeKind.binaryType, raw: text);
    }
    if (RegExp(r'^-?\d+$').hasMatch(text)) {
      return _ParsedType(_TypeKind.numberType, raw: text);
    }
    if (RegExp(r'^"[^"]*"$').hasMatch(text)) {
      return _ParsedType(_TypeKind.inlineEnumType,
          values: {text.substring(1, text.length - 1)}, raw: text);
    }
    if (text.startsWith('Record<')) {
      return _ParsedType(_TypeKind.anyType, raw: text);
    }
    if (text.contains('|')) {
      final parts = splitTopLevelUnion(text);
      // A `|` nested inside generics is not a union of this type.
      if (parts.length > 1) {
        final literals = <String>{};
        var allLiterals = true;
        for (final part in parts) {
          final literal = RegExp(r'^"([^"]*)"$').firstMatch(part);
          if (literal == null) {
            allLiterals = false;
            break;
          }
          literals.add(literal.group(1)!);
        }
        if (allLiterals) {
          return _ParsedType(_TypeKind.inlineEnumType,
              values: literals, raw: text);
        }
        return _ParsedType(_TypeKind.unionType, raw: text);
      }
    }
    if (text.endsWith('[]')) {
      return _ParsedType(_TypeKind.listType,
          inner: _parseFirefoxType(text.substring(0, text.length - 2)),
          raw: text);
    }
    final array = _genericArgument(text, 'Array');
    if (array != null) {
      return _ParsedType(_TypeKind.listType,
          inner: _parseFirefoxType(array), raw: text);
    }
    final promise = _genericArgument(text, 'Promise');
    if (promise != null) {
      return _ParsedType(_TypeKind.promiseType,
          inner: _parseFirefoxType(promise), raw: text);
    }
    final event = _genericArgument(text, 'Events.Event');
    if (event != null) {
      return _ParsedType(_TypeKind.eventType, raw: event);
    }
    if (text.contains('=>')) {
      return _ParsedType(_TypeKind.functionType, raw: text);
    }
    if (RegExp(r'^\w+(\.\w+)?$').hasMatch(text)) {
      return _ParsedType(_TypeKind.namedType, name: text, raw: text);
    }
    return _ParsedType(_TypeKind.unknownShape, raw: text);
  }

  /// When [text] is `wrapper<argument>`, returns the argument.
  String? _genericArgument(String text, String wrapper) {
    if (!text.startsWith('$wrapper<') || !text.endsWith('>')) {
      return null;
    }
    final content = balancedAngleContent(text, wrapper.length);
    if (content == null || wrapper.length + content.length + 2 != text.length) {
      return null;
    }
    return content.trim();
  }
}

/// Splits a TypeScript union at top-level `|`.
List<String> splitTopLevelUnion(String text) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '(' || char == '[' || char == '<' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
    } else if (char == '>' && i > 0 && text[i - 1] != '=') {
      depth--;
    } else if (char == '|' && depth == 0) {
      parts.add(text.substring(start, i).trim());
      start = i + 1;
    }
  }
  parts.add(text.substring(start).trim());
  return parts;
}
