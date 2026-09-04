// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `cf-ray` response header, split into its two halves.
library;

/// The parsed value of a `cf-ray` response header.
///
/// The value is a request id, a dash and the data centre code:
/// `8f2a3b4c5d6e7f80-FRA`. The suffix is what the tooltip renders as
/// `colo=FRA`.
final class CfRay {
  const CfRay._({required this.rayId, required this.colo});

  /// The request id: the hex digits before the dash, in the casing the
  /// header carried.
  final String rayId;

  /// The data centre code after the dash, three upper case letters --
  /// `FRA`, `SJC`.
  final String colo;

  @override
  String toString() => '$rayId-$colo';

  /// Parses a `cf-ray` header value.
  ///
  /// Accepts one or more hex digits, a dash, and exactly three upper
  /// case letters. The id length is deliberately not pinned to the
  /// sixteen digits seen today: a longer id would still split cleanly,
  /// and the colo is the half the display needs. Anything else --
  /// missing dash, non-hex id, a suffix that is not three upper case
  /// letters -- returns null (ADR-006).
  static CfRay? tryParse(String text) {
    final separator = text.lastIndexOf('-');
    if (separator <= 0) {
      return null;
    }
    final rayId = text.substring(0, separator);
    final colo = text.substring(separator + 1);
    if (colo.length != 3) {
      return null;
    }
    for (final unit in colo.codeUnits) {
      if (unit < 0x41 || unit > 0x5a) {
        return null;
      }
    }
    for (final unit in rayId.codeUnits) {
      if (!_isHexDigit(unit)) {
        return null;
      }
    }
    return CfRay._(rayId: rayId, colo: colo);
  }

  static bool _isHexDigit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x61 && unit <= 0x66) ||
      (unit >= 0x41 && unit <= 0x46);
}
