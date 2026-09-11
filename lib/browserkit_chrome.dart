// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The Chrome backend.
///
/// The only entry point that reaches package:chrome_extension. Import it in
/// an extension, next to browserkit.dart, and nowhere else. It does not load
/// on the Dart VM, so a test that imports it fails at load rather than
/// quietly running against the wrong thing.
library;

export 'browserkit/backend/backend_chrome.dart';
