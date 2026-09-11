// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Formatting and parsing: pure Dart, no browser at all.
///
/// The module for pure functions, sized by its first consumer, a header
/// inspector. It imports nothing -- not even `browserkit` -- and reports failure as an
/// absent value, not as a `Result` (ADR-006).
library;

export 'fmtkit/cf_ray.dart';
export 'fmtkit/cloudflare.dart';
export 'fmtkit/cloudflare_ranges.dart';
export 'fmtkit/format.dart';
export 'fmtkit/ip_address.dart';
