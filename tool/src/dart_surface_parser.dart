// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Parses one generated `package:chrome_extension` library file into the
/// language-neutral surface model.
///
/// The parser is deliberately strict: a construct it does not recognize
/// is a [FormatException] with a line number, never a silent skip. The
/// input is generated, highly regular code; anything irregular means
/// the assumptions behind this tool no longer hold and the report must
/// not pretend otherwise.
library;

import 'source_text.dart';
import 'surface_model.dart';

/// Parses the generated Dart [source] of [namespace] (API notation,
/// for example `webRequest`).
NamespaceSurface parseChromeNamespace(String source, String namespace) =>
    _DartSurfaceParser(source, namespace).parse();

class _DartSurfaceParser {
  _DartSurfaceParser(String source, this.namespace)
      : text = MaskedSource.of(source, maskStrings: true);

  final String namespace;
  final MaskedSource text;

  final functions = <FunctionMember>[];
  final events = <EventMember>[];
  final propertyNames = <String>[];
  final dictionaries = <String, Dictionary>{};
  final enums = <String, EnumDefinition>{};
  final typeAliases = <String, String>{};

  String get _mainClassName {
    final upper = namespace[0].toUpperCase() + namespace.substring(1);
    return 'Chrome$upper';
  }

  NamespaceSurface parse() {
    final lines = text.maskedLines;
    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty ||
          line == 'library;' ||
          line.startsWith('import ') ||
          line.startsWith('export ') ||
          line.startsWith('final _')) {
        i++;
        continue;
      }
      if (line.startsWith('extension ')) {
        i = _skipBracedBlock(i);
        continue;
      }
      if (line.startsWith('typedef ')) {
        i = _readTypedef(i);
        continue;
      }
      final classMatch = RegExp(r'^class (\w+)').firstMatch(line);
      if (classMatch != null) {
        i = _readClass(i, classMatch.group(1)!);
        continue;
      }
      final enumMatch = RegExp(r'^enum (\w+) \{$').firstMatch(line);
      if (enumMatch != null) {
        i = _readEnum(i, enumMatch.group(1)!);
        continue;
      }
      throw FormatException(
          '$namespace.dart line ${i + 1}: unrecognized top-level construct: '
          '${text.lines[i].trim()}');
    }
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

  /// Consumes a top-level block opened on line [start], returning the
  /// index of the line after its closing brace.
  int _skipBracedBlock(int start) {
    var depth = 0;
    var seenOpen = false;
    for (var i = start; i < text.maskedLines.length; i++) {
      for (final char in text.maskedLines[i].split('')) {
        if (char == '{') {
          depth++;
          seenOpen = true;
        } else if (char == '}') {
          depth--;
        }
      }
      if (seenOpen && depth == 0) {
        return i + 1;
      }
    }
    throw FormatException(
        '$namespace.dart line ${start + 1}: unterminated block');
  }

  int _readTypedef(int start) {
    final buffer = StringBuffer();
    for (var i = start; i < text.maskedLines.length; i++) {
      buffer.write('${text.maskedLines[i]}\n');
      if (text.maskedLines[i].trimRight().endsWith(';')) {
        final match = RegExp(r'^typedef (\w+) = (.+);$')
            .firstMatch(collapseWhitespace(buffer.toString()));
        if (match == null) {
          throw FormatException(
              '$namespace.dart line ${start + 1}: unrecognized typedef');
        }
        typeAliases[match.group(1)!] = match.group(2)!;
        return i + 1;
      }
    }
    throw FormatException(
        '$namespace.dart line ${start + 1}: unterminated typedef');
  }

  int _readEnum(int start, String name) {
    final values = <String>{};
    for (var i = start + 1; i < text.maskedLines.length; i++) {
      final masked = lineTrim(i);
      if (masked == '}') {
        // Values may legally be empty only if the enum had none, which
        // generated code never produces; be strict.
        if (values.isEmpty) {
          throw FormatException(
              '$namespace.dart line ${start + 1}: enum $name has no '
              'recognized values');
        }
        enums[name] = EnumDefinition(name, values);
        return i + 1;
      }
      // The wire value is a string literal, so it must come from the
      // original line, not the masked one.
      final valueMatch = RegExp(r"^\s*\w+\('((?:[^'\\]|\\.)*)'\)[,;]$")
          .firstMatch(text.lines[i]);
      if (valueMatch != null) {
        values.add(valueMatch.group(1)!);
        if (text.lines[i].trimRight().endsWith(';')) {
          // The value list ended; the remainder (const constructor,
          // toJS/fromJS helpers) is boilerplate to skip.
          for (var j = i + 1; j < text.maskedLines.length; j++) {
            if (lineTrim(j) == '}') {
              enums[name] = EnumDefinition(name, values);
              return j + 1;
            }
          }
          break;
        }
        continue;
      }
      if (masked.isEmpty) {
        continue;
      }
      throw FormatException(
          '$namespace.dart line ${i + 1}: unrecognized enum value line: '
          '${text.lines[i].trim()}');
    }
    throw FormatException(
        '$namespace.dart line ${start + 1}: unterminated enum $name');
  }

  String lineTrim(int index) => text.maskedLines[index].trim();

  int _readClass(int start, String name) {
    // The class body: from after the `{` on the start line to the
    // matching close. Generated class headers fit on one line.
    if (!text.maskedLines[start].trimRight().endsWith('{')) {
      throw FormatException(
          '$namespace.dart line ${start + 1}: class header not on one line');
    }
    final end = _skipBracedBlock(start);
    final bodyLines = text.maskedLines.sublist(start + 1, end - 1);
    final declarations = _declarations(bodyLines, start + 1, name);
    if (name == _mainClassName) {
      for (final declaration in declarations) {
        _readMainMember(declaration);
      }
    } else {
      _readDictionary(name, declarations);
    }
    return end;
  }

  /// Splits a class body into member declaration heads. Bodies (both
  /// braced and `=>`) are skipped; annotations are stripped.
  List<_Declaration> _declarations(
      List<String> bodyLines, int lineOffset, String className) {
    final body = bodyLines.join('\n');
    final declarations = <_Declaration>[];
    var i = 0;
    while (i < body.length) {
      if (body[i].trim().isEmpty) {
        i++;
        continue;
      }
      final declarationStart = i;
      final declarationLine =
          lineOffset + '\n'.allMatches(body.substring(0, i)).length;
      var depth = 0;
      String? head;
      while (i < body.length) {
        final char = body[i];
        if (char == '(' || char == '[') {
          depth++;
          i++;
        } else if (char == ')' || char == ']') {
          depth--;
          i++;
        } else if (depth == 0 && char == '{') {
          head = body.substring(declarationStart, i);
          i = _skipBracesAt(body, i, declarationLine);
          break;
        } else if (depth == 0 && char == ';') {
          head = body.substring(declarationStart, i);
          i++;
          break;
        } else if (depth == 0 &&
            char == '=' &&
            i + 1 < body.length &&
            body[i + 1] == '>') {
          head = body.substring(declarationStart, i);
          i = _skipExpressionBodyAt(body, i, declarationLine);
          break;
        } else {
          i++;
        }
      }
      if (head == null) {
        throw FormatException(
            '$namespace.dart line ${declarationLine + 1}: unterminated '
            'declaration in $className');
      }
      final cleaned = _stripAnnotations(collapseWhitespace(head));
      if (cleaned.isNotEmpty) {
        declarations.add(_Declaration(cleaned, declarationLine + 1));
      }
    }
    return declarations;
  }

  /// From [start] pointing at `{`, consumes the balanced braces and
  /// returns the index after the closing one.
  int _skipBracesAt(String body, int start, int line) {
    var depth = 0;
    for (var i = start; i < body.length; i++) {
      if (body[i] == '{') {
        depth++;
      } else if (body[i] == '}') {
        depth--;
        if (depth == 0) {
          return i + 1;
        }
      }
    }
    throw FormatException(
        '$namespace.dart line ${line + 1}: unbalanced braces');
  }

  /// From [start] pointing at the `=` of `=>`, consumes the expression
  /// body up to its terminating `;` and returns the index after it.
  int _skipExpressionBodyAt(String body, int start, int line) {
    var depth = 0;
    for (var i = start; i < body.length; i++) {
      final char = body[i];
      if (char == '(' || char == '[' || char == '{') {
        depth++;
      } else if (char == ')' || char == ']' || char == '}') {
        depth--;
      } else if (char == ';' && depth == 0) {
        return i + 1;
      }
    }
    throw FormatException(
        '$namespace.dart line ${line + 1}: unterminated expression body');
  }

  String _stripAnnotations(String declaration) {
    var result = declaration;
    while (result.startsWith('@')) {
      final open = result.indexOf('(');
      final space = result.indexOf(' ');
      if (open != -1 && (space == -1 || open < space)) {
        var depth = 0;
        var end = -1;
        for (var i = open; i < result.length; i++) {
          if (result[i] == '(') {
            depth++;
          } else if (result[i] == ')') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        if (end == -1) {
          throw FormatException(
              '$namespace.dart: unbalanced annotation in: $declaration');
        }
        result = result.substring(end + 1).trim();
      } else if (space != -1) {
        result = result.substring(space + 1).trim();
      } else {
        return '';
      }
    }
    return result;
  }

  void _readMainMember(_Declaration declaration) {
    final head = declaration.text;
    if (head.startsWith('$_mainClassName._(')) {
      return; // Private constructor, generator boilerplate.
    }
    if (head == 'bool get isAvailable') {
      return; // Generator artifact, not part of the chrome.* surface.
    }
    final event = RegExp(r'^EventStream<(.+)> get (\w+)$').firstMatch(head);
    if (event != null) {
      events.add(_eventFromPayload(event.group(2)!, event.group(1)!));
      return;
    }
    final property = RegExp(r'^(.+) get (\w+)$').firstMatch(head);
    if (property != null) {
      propertyNames.add(property.group(2)!);
      return;
    }
    final method = _parseMethod(head);
    if (method != null) {
      functions.add(method);
      return;
    }
    throw FormatException(
        '$namespace.dart line ${declaration.line}: unrecognized member of '
        '$_mainClassName: $head');
  }

  EventMember _eventFromPayload(String name, String payload) => EventMember(
      name, payload == 'void' ? const [] : [ParameterSpec('', payload.trim())]);

  FunctionMember? _parseMethod(String head) {
    var text = head;
    if (text.endsWith(' async')) {
      text = text.substring(0, text.length - ' async'.length);
    }
    if (!text.endsWith(')')) {
      return null;
    }
    // Find the `(` that opens the parameter list: the one balancing the
    // final `)`.
    var depth = 0;
    var open = -1;
    for (var i = text.length - 1; i >= 0; i--) {
      if (text[i] == ')') {
        depth++;
      } else if (text[i] == '(') {
        depth--;
        if (depth == 0) {
          open = i;
          break;
        }
      }
    }
    if (open <= 0) {
      return null;
    }
    final beforeParameters = text.substring(0, open).trim();
    final nameMatch = RegExp(r'^(.*\S) (\w+)$').firstMatch(beforeParameters);
    if (nameMatch == null) {
      return null;
    }
    final returnType = nameMatch.group(1)!;
    final name = nameMatch.group(2)!;
    final rawParameters = text.substring(open + 1, text.length - 1);
    if (rawParameters.contains('{') || rawParameters.contains('[')) {
      throw FormatException(
          '$namespace.dart: named or bracketed optional parameters in '
          '$name are not a shape this parser knows: $head');
    }
    final parameters = <ParameterSpec>[];
    for (final part in splitTopLevel(rawParameters)) {
      final parameter = RegExp(r'^(.*\S) (\w+)$').firstMatch(part);
      if (parameter == null) {
        throw FormatException(
            '$namespace.dart: unrecognized parameter "$part" in: $head');
      }
      var type = parameter.group(1)!;
      final optional = type.endsWith('?');
      if (optional) {
        type = type.substring(0, type.length - 1);
      }
      parameters
          .add(ParameterSpec(parameter.group(2)!, type, optional: optional));
    }
    return FunctionMember(name, [FunctionSignature(parameters, returnType)]);
  }

  void _readDictionary(String name, List<_Declaration> declarations) {
    final fields = <DictionaryField>[];
    final methodNames = <String>{};
    for (final declaration in declarations) {
      final head = declaration.text;
      if (head.startsWith('$name.') || head.startsWith('$name(')) {
        continue; // Constructors, including `.fromJS`.
      }
      if (head.startsWith('set ')) {
        continue; // Setters mirror the getters; the getter carries the type.
      }
      final getter = RegExp(r'^(.+) get (\w+)$').firstMatch(head);
      if (getter != null) {
        _addField(fields, getter.group(2)!, getter.group(1)!);
        continue;
      }
      // A final field may carry an initializer; the declaration part
      // before ` = ` is what carries type and name.
      final finalField = RegExp(r'^final (.+) (\w+)$')
          .firstMatch(head.replaceFirst(RegExp(' = .*'), ''));
      if (finalField != null) {
        _addField(fields, finalField.group(2)!, finalField.group(1)!);
        continue;
      }
      final method = _parseMethod(head);
      if (method != null) {
        methodNames.add(method.name);
        continue;
      }
      throw FormatException(
          '$namespace.dart line ${declaration.line}: unrecognized member of '
          '$name: $head');
    }
    dictionaries[name] = Dictionary(name, fields, methodNames: methodNames);
  }

  void _addField(List<DictionaryField> fields, String name, String rawType) {
    if (name.startsWith('_') || name == 'toJS') {
      return; // Private backing storage and interop boilerplate.
    }
    var type = rawType.trim();
    final optional = type.endsWith('?');
    if (optional) {
      type = type.substring(0, type.length - 1);
    }
    fields.add(DictionaryField(name, type, optional: optional));
  }
}

class _Declaration {
  const _Declaration(this.text, this.line);

  final String text;
  final int line;
}
