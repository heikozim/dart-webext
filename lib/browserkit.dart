// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The portable half of browserkit: everything that does not need a browser.
///
/// Import this from any module and from every test. It carries the facades,
/// the error taxonomy, the result type, the library vocabulary and the
/// abstract backend, and it reaches no browser binding at all.
///
/// The two implementations live behind their own entry points, so that a
/// consumer cannot pull one in by accident:
///
/// * `browserkit_chrome.dart` for the real browser, and
/// * `browserkit_fake.dart` for tests.
///
/// That split is what keeps the one-binding rule checkable rather than
/// merely stated: only one file in this package imports
/// package:chrome_extension, and it is not reachable from here.
library;

export 'browserkit/api/action.dart';
export 'browserkit/api/alarms.dart';
export 'browserkit/api/permissions.dart';
export 'browserkit/api/runtime.dart';
export 'browserkit/api/scripting.dart';
export 'browserkit/api/storage.dart';
export 'browserkit/api/tabs.dart';
export 'browserkit/api/web_request.dart';
export 'browserkit/backend/backend.dart';
export 'browserkit/error.dart';
export 'browserkit/result.dart';
export 'browserkit/types.dart';
