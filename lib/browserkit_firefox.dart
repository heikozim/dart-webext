// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The Firefox entry point: `FirefoxBackend` over the `browser.*`
/// surface (ADR-007). The consumer chooses the backend at build time
/// by importing this file or `browserkit_chrome.dart` -- it maintains
/// two manifests anyway, and the library deliberately carries no
/// auto-detection (decision of 2026-09-02).
///
/// BUILD IN PROGRESS: webRequest is bound and measured; every other
/// namespace still answers `NotAvailable` with a "not yet bound"
/// detail -- see `backend/backend_firefox.dart` for the per-namespace
/// state and the schema provenance.
///
/// Like the Chrome entry point, this file only loads in a browser.
library;

export 'browserkit/backend/backend_firefox.dart' show FirefoxBackend;
