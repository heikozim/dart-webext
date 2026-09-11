// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Display formatting for the header inspector: time to first byte,
/// badge text, capture time, and the two header list settings.
///
/// Everything here follows the header inspector's specification to the
/// letter; the section is cited at each function.
library;

/// The time to first byte as seconds with three decimals: `0.263`.
///
/// The tooltip shows this value (spec section 4). Three decimals because
/// `webRequest` timestamps have millisecond resolution; more digits
/// would be invented precision. Returns null when [milliseconds] is
/// negative, infinite or NaN -- no such duration comes from a pair of
/// ordered timestamps, so there is nothing truthful to display
/// (ADR-006).
String? formatTimeToFirstByteSeconds(double milliseconds) {
  if (!milliseconds.isFinite || milliseconds < 0) {
    return null;
  }
  return (milliseconds / 1000).toStringAsFixed(3);
}

/// The badge text for a time to first byte (spec section 3): whole
/// milliseconds as a bare number, and from one second on whole seconds
/// with a trailing `s` -- four characters being the practical badge
/// limit.
///
/// Rounds to the nearest unit, halves away from zero; `999.5` and above
/// is therefore already `1s`. Returns null for negative, infinite or
/// NaN input, like [formatTimeToFirstByteSeconds] (ADR-006).
String? formatBadgeDuration(double milliseconds) {
  if (!milliseconds.isFinite || milliseconds < 0) {
    return null;
  }
  final wholeMilliseconds = milliseconds.round();
  if (wholeMilliseconds < 1000) {
    return '$wholeMilliseconds';
  }
  return '${(milliseconds / 1000).round()}s';
}

/// The capture time opening the first tooltip line: `18:32`.
/// Twenty-four hour clock, zero padded (spec section 4).
String formatClockTime(DateTime time) {
  final hours = time.hour.toString().padLeft(2, '0');
  final minutes = time.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}

/// Collapses repeated headers to their first occurrence, keeping the
/// arrival order -- the first of the two list settings of spec
/// section 8.
///
/// Header names compare case-insensitively, as HTTP defines them.
/// [nameOf] extracts the name: fmtkit depends on nothing, so it cannot
/// name browserkit's header type, and the selector keeps it that way.
/// Returns a new unmodifiable list; [headers] is not touched.
List<T> collapseRepeatedHeaders<T>(
  List<T> headers,
  String Function(T header) nameOf,
) {
  final seenNames = <String>{};
  final collapsed = <T>[];
  for (final header in headers) {
    if (seenNames.add(nameOf(header).toLowerCase())) {
      collapsed.add(header);
    }
  }
  return List<T>.unmodifiable(collapsed);
}

/// Sorts headers alphabetically by name -- the second list setting of
/// spec section 8.
///
/// Names compare case-insensitively, so `accept` does not sort behind
/// `Server`. The sort is stable: headers with equal names keep their
/// arrival order, which matters when repeats are not collapsed. Returns
/// a new unmodifiable list; [headers] is not touched.
List<T> sortHeadersByName<T>(
  List<T> headers,
  String Function(T header) nameOf,
) {
  final indexed = headers.indexed.toList()
    ..sort((first, second) {
      final byName = nameOf(first.$2)
          .toLowerCase()
          .compareTo(nameOf(second.$2).toLowerCase());
      if (byName != 0) {
        return byName;
      }
      return first.$1 - second.$1;
    });
  return List<T>.unmodifiable(indexed.map((entry) => entry.$2));
}
