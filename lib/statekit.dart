// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// State that survives service worker restarts.
///
/// The module above `browserkit`: it touches no browser API itself and
/// speaks to the browser only
/// through the injectable `Backend`. Import it next to `browserkit.dart`;
/// it reaches no browser binding, so everything here runs under `dart test`
/// against the fake backend.
library;

export 'statekit/tab_store.dart';
