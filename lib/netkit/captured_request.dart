// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// What netkit captures: one request with its whole redirect chain.
library;

import '../browserkit/types.dart';

/// One hop of a request: what left, and what answered.
///
/// A plain navigation has one hop; a redirected one has one per jump, in
/// order (measured: `onSendHeaders` and `onHeadersReceived` fire per hop
/// under one request id, ADR-005). The response half stays empty until the
/// answer of this hop arrives.
final class RequestHop {
  /// Describes one hop.
  const RequestHop({
    required this.url,
    required this.method,
    required this.requestHeaders,
    required this.sentAt,
    required this.statusCode,
    required this.responseHeaders,
    required this.receivedAt,
  });

  /// The address this hop was sent to.
  final String url;

  /// The HTTP method of this hop. A redirect can change it.
  final String method;

  /// The request headers of this hop, in order, repetitions preserved.
  /// Unmodifiable.
  final List<HttpHeader> requestHeaders;

  /// When the request headers left, in milliseconds since the epoch.
  final double sentAt;

  /// The status code this hop answered with, or null while unanswered.
  final int? statusCode;

  /// The response headers of this hop, in order, repetitions preserved.
  /// Unmodifiable; empty while unanswered.
  final List<HttpHeader> responseHeaders;

  /// When the response headers of this hop arrived, or null while
  /// unanswered. Milliseconds since the epoch.
  final double? receivedAt;

  @override
  String toString() =>
      'RequestHop(method: $method, url: $url, statusCode: $statusCode)';
}

/// One captured request of a tab: the redirect chain as one entry.
///
/// Built up from the three webRequest events of one request id. The chain
/// lives in [hops]; the final answer -- status, server address, cache flag,
/// first-byte time -- arrives with `onResponseStarted` and fills the
/// remaining fields, which stay null until then.
final class CapturedRequest {
  /// Describes one captured request.
  const CapturedRequest({
    required this.requestId,
    required this.tabId,
    required this.resourceType,
    required this.hops,
    required this.finalStatusCode,
    required this.ip,
    required this.fromCache,
    required this.startedAt,
  });

  /// Identifies the request, uniquely within a browser session and stable
  /// across the hops of its chain.
  final String requestId;

  /// The tab the request belongs to.
  final int tabId;

  /// What kind of resource was requested, as the browser names it.
  final String resourceType;

  /// The hops of the chain, oldest first, at least one. Unmodifiable.
  final List<RequestHop> hops;

  /// The status code of the final answer, or null until the first byte
  /// arrived.
  final int? finalStatusCode;

  /// The server address of the final answer, or null when the browser
  /// reports none or the first byte has not arrived yet.
  final String? ip;

  /// Whether the final answer came from cache, or null until the first
  /// byte arrived.
  final bool? fromCache;

  /// When the first byte of the final answer was available, or null until
  /// then. Milliseconds since the epoch.
  final double? startedAt;

  /// Whether this is the main document request of its tab.
  bool get isMainFrame => resourceType == 'main_frame';

  /// The address the chain ended at.
  String get finalUrl => hops.last.url;

  /// Time to first byte in milliseconds, measured from the FIRST send of
  /// the chain to the first byte of the final answer -- the wait the user
  /// actually experienced, redirects included. Null until the first byte
  /// arrived.
  double? get timeToFirstByteMilliseconds {
    final started = startedAt;
    if (started == null) {
      return null;
    }
    return started - hops.first.sentAt;
  }

  @override
  String toString() => 'CapturedRequest(requestId: $requestId, '
      'tabId: $tabId, resourceType: $resourceType, hops: ${hops.length}, '
      'finalStatusCode: $finalStatusCode)';
}
