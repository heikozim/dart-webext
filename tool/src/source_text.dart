// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Text-level helpers shared by both surface parsers.
///
/// The parsers work on a masked copy of the source in which comment
/// content -- and, where requested, string-literal content -- is
/// replaced by spaces. Masking keeps every line at its original length,
/// so an index into the masked text is also an index into the original.
library;

/// A source file next to a masked copy of itself.
///
/// The masked copy blanks comment content (and optionally string
/// content) with spaces while preserving line structure, so structural
/// scanning cannot be fooled by braces or parentheses inside comments
/// or strings. Both representations split into [lines] identically.
class MaskedSource {
  MaskedSource._(this.original, this.masked)
      : lines = original.split('\n'),
        maskedLines = masked.split('\n');

  /// Masks [source]. With [maskStrings] the content of string literals
  /// is blanked too (the quotes stay); string interpolation content is
  /// then blanked along with the rest, which is exactly what a
  /// structural scanner needs.
  factory MaskedSource.of(String source, {required bool maskStrings}) {
    final out = StringBuffer();
    var index = 0;
    while (index < source.length) {
      if (source.startsWith('//', index)) {
        final end = source.indexOf('\n', index);
        final stop = end == -1 ? source.length : end;
        out.write(' ' * (stop - index));
        index = stop;
      } else if (source.startsWith('/*', index)) {
        final end = source.indexOf('*/', index + 2);
        final stop = end == -1 ? source.length : end + 2;
        for (var i = index; i < stop; i++) {
          out.write(source[i] == '\n' ? '\n' : ' ');
        }
        index = stop;
      } else if (source[index] == "'" || source[index] == '"') {
        final quote = source[index];
        out.write(quote);
        index++;
        while (index < source.length && source[index] != quote) {
          if (source[index] == r'\' && index + 1 < source.length) {
            out.write(maskStrings ? '  ' : source.substring(index, index + 2));
            index += 2;
            continue;
          }
          if (source[index] == '\n') {
            // An unterminated literal on one line: stop masking at the
            // line end rather than eating the rest of the file.
            break;
          }
          out.write(maskStrings ? ' ' : source[index]);
          index++;
        }
        if (index < source.length && source[index] == quote) {
          out.write(quote);
          index++;
        }
      } else {
        out.write(source[index]);
        index++;
      }
    }
    return MaskedSource._(source, out.toString());
  }

  /// The source exactly as fetched.
  final String original;

  /// The masked copy, same length and line structure as [original].
  final String masked;

  /// [original] split into lines.
  final List<String> lines;

  /// [masked] split into lines.
  final List<String> maskedLines;
}

/// Splits [text] at top-level commas, ignoring commas nested inside
/// parentheses, brackets, braces or angle brackets. Empty segments are
/// dropped (a trailing comma produces one).
List<String> splitTopLevel(String text) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '(' || char == '[' || char == '{' || char == '<') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}' || char == '>') {
      // `=>` must not close an angle level.
      if (!(char == '>' && i > 0 && text[i - 1] == '=')) {
        depth--;
      }
    } else if (char == ',' && depth == 0) {
      parts.add(text.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(text.substring(start));
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Collapses every whitespace run in [text] to one space and trims.
String collapseWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Returns the content between the `<` at [openIndex] and its balancing
/// `>` in [text], or null when the brackets do not balance. `=>` inside
/// the brackets is understood as an arrow, not as a closer.
String? balancedAngleContent(String text, int openIndex) {
  assert(text[openIndex] == '<', 'openIndex must point at "<"');
  var depth = 0;
  for (var i = openIndex; i < text.length; i++) {
    final char = text[i];
    if (char == '<') {
      depth++;
    } else if (char == '>' && text[i - 1] != '=') {
      depth--;
      if (depth == 0) {
        return text.substring(openIndex + 1, i);
      }
    }
  }
  return null;
}
