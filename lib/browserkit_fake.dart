// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The fake backend, for tests.
///
/// Plain Dart, no interop, no browser. Kept out of browserkit.dart so that a
/// production bundle does not carry the test double.
library;

export 'browserkit/backend/backend_fake.dart';
