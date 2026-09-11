// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Parses one generated Lusito `.d.ts` namespace file into the
/// language-neutral surface model.
///
/// Strict on principle, like the Dart parser: a member shape this
/// parser does not know is a [FormatException] with a line number, not
/// a silent skip.
library;

import 'source_text.dart';
import 'surface_model.dart';

/// Parses the generated TypeScript declaration [source] of [namespace]
/// (API notation, for example `webRequest`).
NamespaceSurface parseFirefoxNamespace(String source, String namespace) =>
    _TsSurfaceParser(source, namespace).parse();

class _TsSurfaceParser {
  _TsSurfaceParser(String source, this.namespace)
      : text = MaskedSource.of(source, maskStrings: false);

  final String namespace;
  final MaskedSource text;

  final functions = <FunctionMember>[];
  final events = <EventMember>[];
  final propertyNames = <String>[];
  final dictionaries = <String, Dictionary>{};
  final enums = <String, EnumDefinition>{};
  final typeAliases = <String, String>{};

  /// Event interfaces (`interface X extends Events.Event<...>`), by
  /// name: callback parameters plus the addListener parameters beyond
  /// the callback.
  final _eventInterfaces =
      <String, ({List<ParameterSpec> callback, List<ParameterSpec> extras})>{};

  /// Members of `interface Static`, kept until the event interfaces of
  /// the whole file are known.
  final _staticMembers = <_InterfaceMember>[];

  NamespaceSurface parse() {
    final lines = text.maskedLines;
    var i = 0;
    var sawNamespace = false;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('import ')) {
        i++;
        continue;
      }
      final namespaceMatch =
          RegExp(r'^export namespace (\w+) \{$').firstMatch(line);
      if (namespaceMatch != null) {
        sawNamespace = true;
        i = _readNamespaceBody(i);
        continue;
      }
      throw FormatException(
          '$namespace.d.ts line ${i + 1}: unrecognized top-level construct: '
          '${text.lines[i].trim()}');
    }
    if (!sawNamespace) {
      throw FormatException('$namespace.d.ts: no export namespace found');
    }
    _resolveStaticMembers();
    return NamespaceSurface(
      namespace: namespace,
      functions: functions,
      events: events,
      propertyNames: propertyNames,
      dictionaries: dictionaries,
      enums: enums,
      typeAliases: typeAliases,
    );
  }

  int _readNamespaceBody(int start) {
    final end = _blockEnd(start);
    var i = start + 1;
    while (i < end) {
      final line = text.maskedLines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      if (line.startsWith('interface ')) {
        i = _readInterface(i);
        continue;
      }
      if (line.startsWith('type ')) {
        i = _readTypeAlias(i);
        continue;
      }
      throw FormatException(
          '$namespace.d.ts line ${i + 1}: unrecognized namespace member: '
          '${text.lines[i].trim()}');
    }
    return end + 1;
  }

  /// Returns the line index of the `}` closing the block whose opening
  /// brace sits on or after line [start].
  int _blockEnd(int start) {
    var depth = 0;
    var seenOpen = false;
    for (var i = start; i < text.maskedLines.length; i++) {
      for (final char in text.maskedLines[i].split('')) {
        if (char == '{') {
          depth++;
          seenOpen = true;
        } else if (char == '}') {
          depth--;
          if (seenOpen && depth == 0) {
            return i;
          }
        }
      }
    }
    throw FormatException(
        '$namespace.d.ts line ${start + 1}: unterminated block');
  }

  int _readTypeAlias(int start) {
    final buffer = StringBuffer();
    for (var i = start; i < text.maskedLines.length; i++) {
      buffer.write('${text.maskedLines[i]}\n');
      if (text.maskedLines[i].trimRight().endsWith(';')) {
        final head = collapseWhitespace(buffer.toString());
        final match = RegExp(r'^type (\w+) = (.+);$').firstMatch(head);
        if (match == null) {
          throw FormatException(
              '$namespace.d.ts line ${start + 1}: unrecognized type alias');
        }
        final name = match.group(1)!;
        final rightHandSide = match.group(2)!;
        final union = _stringLiteralUnion(rightHandSide);
        if (union != null) {
          enums[name] = EnumDefinition(name, union);
        } else {
          typeAliases[name] = rightHandSide;
        }
        return i + 1;
      }
    }
    throw FormatException(
        '$namespace.d.ts line ${start + 1}: unterminated type alias');
  }

  /// Returns the literal values when [rightHandSide] is a union made
  /// only of string literals, otherwise null.
  Set<String>? _stringLiteralUnion(String rightHandSide) {
    final values = <String>{};
    for (final part in rightHandSide.split('|')) {
      final literal = RegExp(r'^"([^"]*)"$').firstMatch(part.trim());
      if (literal == null) {
        return null;
      }
      values.add(literal.group(1)!);
    }
    return values;
  }

  int _readInterface(int start) {
    // The header may spread over lines before its `{` (a long extends
    // clause does that), so fold until the first `{` at paren depth 0.
    final headerBuffer = StringBuffer();
    var bodyStart = -1;
    var depth = 0;
    for (var i = start; i < text.maskedLines.length && bodyStart == -1; i++) {
      final line = text.maskedLines[i];
      for (var c = 0; c < line.length; c++) {
        final char = line[c];
        if (char == '(' || char == '<') {
          depth++;
        } else if (char == ')') {
          depth--;
        } else if (char == '>' && c > 0 && line[c - 1] != '=') {
          depth--;
        } else if (char == '{' && depth == 0) {
          headerBuffer.write(line.substring(0, c));
          bodyStart = i;
          break;
        }
      }
      if (bodyStart == -1) {
        headerBuffer.write('$line\n');
      }
    }
    if (bodyStart == -1) {
      throw FormatException(
          '$namespace.d.ts line ${start + 1}: interface header without body');
    }
    final header = collapseWhitespace(headerBuffer.toString());
    final headerMatch =
        RegExp(r'^interface (\w+)( extends (.+))?$').firstMatch(header);
    if (headerMatch == null) {
      throw FormatException(
          '$namespace.d.ts line ${start + 1}: unrecognized interface '
          'header: $header');
    }
    final name = headerMatch.group(1)!;
    final extendsClause = headerMatch.group(3);
    final end = _blockEnd(bodyStart);
    final members = _members(bodyStart, end, name);

    final eventBase = extendsClause == null
        ? null
        : RegExp(r'^Events\.Event<(.+)>$').firstMatch(extendsClause);
    if (eventBase != null) {
      _registerEventInterface(name, eventBase.group(1)!, members, start);
    } else if (name == 'Static') {
      _staticMembers.addAll(members);
    } else {
      _registerDictionary(name, extendsClause, members);
    }
    return end + 1;
  }

  /// Folds the member declarations between the braces of an interface
  /// body. Members end with `;` at brace/paren/bracket depth 0.
  List<_InterfaceMember> _members(int bodyStart, int end, String owner) {
    final firstLine = text.maskedLines[bodyStart];
    final afterBrace = firstLine.substring(firstLine.indexOf('{') + 1);
    final bodyLines = <String>[
      afterBrace,
      ...text.maskedLines.sublist(bodyStart + 1, end),
      // The closing line up to its `}` belongs to the body too.
      text.maskedLines[end].substring(0, text.maskedLines[end].indexOf('}')),
    ];
    final body = bodyLines.join('\n');
    final members = <_InterfaceMember>[];
    var i = 0;
    while (i < body.length) {
      if (body[i].trim().isEmpty) {
        i++;
        continue;
      }
      final memberStart = i;
      final memberLine =
          bodyStart + '\n'.allMatches(body.substring(0, i)).length;
      var depth = 0;
      var head = '';
      var terminated = false;
      for (; i < body.length; i++) {
        final char = body[i];
        if (char == '(' || char == '[' || char == '{') {
          depth++;
        } else if (char == ')' || char == ']' || char == '}') {
          depth--;
        } else if (char == ';' && depth == 0) {
          head = body.substring(memberStart, i);
          i++;
          terminated = true;
          break;
        }
      }
      if (!terminated) {
        throw FormatException(
            '$namespace.d.ts line ${memberLine + 1}: unterminated member '
            'of $owner');
      }
      members.add(_InterfaceMember(collapseWhitespace(head), memberLine + 1));
    }
    return members;
  }

  void _registerEventInterface(String name, String callbackSignature,
      List<_InterfaceMember> members, int startLine) {
    final callback = _callbackParameters(callbackSignature, startLine + 1);
    List<ParameterSpec> extras = const [];
    for (final member in members) {
      final addListener =
          RegExp(r'^addListener\((.+)\): void$').firstMatch(member.text);
      if (addListener != null) {
        final parts = splitTopLevel(addListener.group(1)!);
        if (parts.isEmpty) {
          throw FormatException(
              '$namespace.d.ts line ${member.line}: addListener of $name '
              'without a callback parameter');
        }
        extras = [
          for (final part in parts.skip(1)) _parameter(part, member.line),
        ];
      }
      // removeListener/hasListener carry no extra information.
    }
    _eventInterfaces[name] = (callback: callback, extras: extras);
  }

  /// Parses `(a: T, b: U) => void` into its parameters. [line] is
  /// 1-based and only used for error messages.
  List<ParameterSpec> _callbackParameters(String signature, int line) {
    final match = RegExp(r'^\((.*)\) => .+$').firstMatch(signature.trim());
    if (match == null) {
      throw FormatException('$namespace.d.ts line $line: unrecognized callback '
          'signature: $signature');
    }
    return [
      for (final part in splitTopLevel(match.group(1)!)) _parameter(part, line),
    ];
  }

  ParameterSpec _parameter(String part, int line) {
    final match = RegExp(r'^(\w+)(\?)?: (.+)$').firstMatch(part.trim());
    if (match == null) {
      throw FormatException(
          '$namespace.d.ts line $line: unrecognized parameter: $part');
    }
    var type = match.group(3)!.trim();
    var optional = match.group(2) != null;
    if (type.endsWith(' | undefined')) {
      type = type.substring(0, type.length - ' | undefined'.length).trim();
      optional = true;
    }
    return ParameterSpec(match.group(1)!, type, optional: optional);
  }

  void _registerDictionary(
      String name, String? extendsClause, List<_InterfaceMember> members) {
    final fields = <DictionaryField>[];
    final methodNames = <String>{};
    var hasIndexSignature = false;
    for (final member in members) {
      final head = member.text;
      if (RegExp(r'^\[\w+: string\]: .+$').hasMatch(head)) {
        hasIndexSignature = true;
        continue;
      }
      final method = RegExp(r'^(\w+)\??(<.+>)?\(').firstMatch(head);
      if (method != null) {
        methodNames.add(method.group(1)!);
        continue;
      }
      final field = RegExp(r'^(\w+)(\?)?: (.+)$').firstMatch(head);
      if (field != null) {
        var type = field.group(3)!.trim();
        var optional = field.group(2) != null;
        if (type.endsWith(' | undefined')) {
          type = type.substring(0, type.length - ' | undefined'.length).trim();
          optional = true;
        }
        fields.add(DictionaryField(field.group(1)!, type, optional: optional));
        continue;
      }
      throw FormatException(
          '$namespace.d.ts line ${member.line}: unrecognized member of '
          '$name: $head');
    }
    dictionaries[name] = Dictionary(
      name,
      fields,
      methodNames: methodNames,
      extendedTypes:
          extendsClause == null ? const [] : splitTopLevel(extendsClause),
      hasIndexSignature: hasIndexSignature,
    );
  }

  void _resolveStaticMembers() {
    final overloads = <String, List<FunctionSignature>>{};
    final order = <String>[];
    for (final member in _staticMembers) {
      final head = member.text;
      final inlineEvent =
          RegExp(r'^(on\w+): Events\.Event<(.+)>$').firstMatch(head);
      if (inlineEvent != null) {
        final content = inlineEvent.group(2)!.trim();
        events.add(content.startsWith('(')
            ? EventMember(inlineEvent.group(1)!,
                _callbackParameters(content, member.line))
            : EventMember(inlineEvent.group(1)!, const [],
                unresolvedCallbackType: content));
        continue;
      }
      final namedEvent = RegExp(r'^(on\w+): (\w+)$').firstMatch(head);
      if (namedEvent != null) {
        final resolved = _eventInterfaces[namedEvent.group(2)!];
        if (resolved == null) {
          throw FormatException('$namespace.d.ts line ${member.line}: event '
              '${namedEvent.group(1)!} references ${namedEvent.group(2)!}, '
              'which is not an event interface of this file');
        }
        events.add(EventMember(namedEvent.group(1)!, resolved.callback,
            registrationParameters: resolved.extras));
        continue;
      }
      final function = _parseStaticFunction(head, member.line);
      if (function != null) {
        overloads.putIfAbsent(function.name, () {
          order.add(function.name);
          return [];
        }).addAll(function.overloads);
        continue;
      }
      final property = RegExp(r'^(\w+)(\?)?: (.+)$').firstMatch(head);
      if (property != null) {
        propertyNames.add(property.group(1)!);
        continue;
      }
      throw FormatException(
          '$namespace.d.ts line ${member.line}: unrecognized member of '
          'Static: $head');
    }
    for (final name in order) {
      functions.add(FunctionMember(name, overloads[name]!));
    }
  }

  FunctionMember? _parseStaticFunction(String head, int line) {
    final match = RegExp(r'^(\w+)(<(.+?)>)?\((.*)\): (.+)$').firstMatch(head);
    if (match == null || match.group(1)!.startsWith('on')) {
      return null;
    }
    final name = match.group(1)!;
    final genericParameters = <String>[];
    final genericList = match.group(3);
    if (genericList != null) {
      for (final part in splitTopLevel(genericList)) {
        genericParameters.add(part.split('=').first.trim().split(' ').first);
      }
    }
    String substituteGenerics(String type) {
      var result = type;
      for (final generic in genericParameters) {
        result = result.replaceAll(RegExp('\\b$generic\\b'), 'any');
      }
      return result;
    }

    final parameters = <ParameterSpec>[];
    for (final part in splitTopLevel(match.group(4)!)) {
      final parameter = _parameter(part, line);
      parameters.add(ParameterSpec(
          parameter.name, substituteGenerics(parameter.type),
          optional: parameter.optional));
    }
    final returnType = substituteGenerics(match.group(5)!.trim());
    return FunctionMember(name, [FunctionSignature(parameters, returnType)]);
  }
}

class _InterfaceMember {
  const _InterfaceMember(this.text, this.line);

  final String text;
  final int line;
}
