// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// webRequest capture, request/response pairing, timing.
///
/// The module for network capture, sized by its first consumer, a header
/// inspector. It touches no browser API itself: events arrive through the `WebRequestApi`
/// facade, state survives worker restarts through `statekit`. Import it
/// next to `browserkit.dart` and `statekit.dart`; it reaches no browser
/// binding.
library;

export 'netkit/captured_request.dart';
export 'netkit/request_capture.dart';
