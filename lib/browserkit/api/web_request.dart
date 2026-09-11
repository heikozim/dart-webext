// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `webRequest` facade: request and response header capture.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';
import '../types.dart';

/// Request and response header capture.
///
/// Follows the facade pattern documented on `RuntimeApi`, with one visible
/// difference: the two event surfaces are methods returning a [Result], not
/// bare stream getters. Registration here is parameterised (the browser
/// wants a filter and an extraInfoSpec, both fixed by this library) and can
/// fail -- most plainly with [NotAvailable] when the manifest lacks the
/// `webRequest` permission -- and a failure must arrive as a value. See
/// ADR-004 for why this namespace is also the one bound by hand.
///
/// Observed are http and https requests. What the extension may actually
/// see is bounded by its host permissions: a request to a host outside them
/// simply never appears, which is a permission statement, not a failure.
final class WebRequestApi {
  /// Binds the facade to the given [Backend].
  const WebRequestApi(this._backend);

  final Backend _backend;

  /// The stream of outgoing requests, headers included.
  ///
  /// Pair events with their response through [RequestHeadersSent.requestId].
  /// Each successful call returns a broadcast stream; the caller owns and
  /// cancels the subscription, and the browser listener lives exactly as
  /// long as it.
  Result<Stream<RequestHeadersSent>, BrowserError> onSendHeaders() =>
      _backend.webRequest.onSendHeaders();

  /// The stream of arrived response header blocks, one per hop.
  ///
  /// The only event of the set that sees a redirect chain: each 302 with
  /// its `Location` arrives here, sharing the request id of the final
  /// answer (ADR-005). Subscription rules as on [onSendHeaders].
  Result<Stream<ResponseHeadersReceived>, BrowserError> onHeadersReceived() =>
      _backend.webRequest.onHeadersReceived();

  /// The stream of final responses: first byte available, once per request.
  ///
  /// This is where `ip` and `fromCache` live, and the TTFB measuring
  /// point: the difference between [ResponseStarted.timeStamp] and the
  /// first paired [RequestHeadersSent.timeStamp] is the time to first
  /// byte, the quantity `curl` calls `time_starttransfer` (ADR-005).
  /// Subscription rules as on [onSendHeaders].
  Result<Stream<ResponseStarted>, BrowserError> onResponseStarted() =>
      _backend.webRequest.onResponseStarted();
}
