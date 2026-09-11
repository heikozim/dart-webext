// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The capture service: webRequest events in, per-tab request state out.
library;

import 'dart:async';

import '../browserkit/backend/backend.dart';
import '../browserkit/error.dart';
import '../browserkit/result.dart';
import '../browserkit/types.dart';
import '../statekit/tab_store.dart';
import 'captured_request.dart';

/// Captures the requests of every tab, survives service worker restarts.
///
/// Subscribes to the three webRequest events (ADR-005) and folds them into
/// one [CapturedRequest] per request id, the redirect chain as hops on the
/// same entry. State lives in a [TabStore], written through on every event,
/// so a capture that began before a worker death continues after it: the
/// next event finds its entry in `storage.session`, not in memory.
///
/// Sizing per the header inspector's specification: at most
/// [maxRequestsPerTab] entries per tab, oldest evicted first -- except the
/// main document request, which is never evicted. A new main document
/// request (a navigation) drops the tab's previous capture, matching the
/// specification's lifetime rule. A response whose request was never seen
/// is dropped: capture begins at the send.
final class RequestCapture {
  /// Creates a capture over [backend].
  ///
  /// [onError] receives the failures of event handling and of the
  /// automatic per-tab cleanup; like `TabStore.onCleanupError` it is
  /// required, because those paths have no caller to return a [Result] to.
  /// [maxRequestsPerTab] bounds the per-tab state (ARCHITECTURE.md 7.2:
  /// the caller bounds the state, because `storage.session` has a quota).
  /// [onTabChanged] is invoked with the tab id after every successful
  /// write of that tab's capture state -- the signal a consumer needs to
  /// re-derive whatever it presents from the state (toolbar icon, badge,
  /// tooltip) without subscribing to the webRequest events a second time.
  /// It is called synchronously from the internal work queue, so it must
  /// not block; reading the new state through [requestsForTab] from an
  /// async continuation is safe, the read waits for the queued work
  /// first. It does not fire for the automatic cleanup when a tab
  /// closes -- the browser drops per-tab toolbar state by itself.
  RequestCapture({
    required Backend backend,
    required void Function(BrowserError error) onError,
    this.maxRequestsPerTab = 50,
    void Function(int tabId)? onTabChanged,
  })  : _backend = backend,
        _onError = onError,
        _onTabChanged = onTabChanged {
    _store = TabStore<List<CapturedRequest>>(
      backend: backend,
      namespace: 'netkit-capture',
      codec: const TabStoreCodec<List<CapturedRequest>>(
        encode: _encodeRequests,
        decode: _decodeRequests,
      ),
      onCleanupError: onError,
    );
  }

  /// The per-tab entry limit. At least 1; checked by [start].
  final int maxRequestsPerTab;

  final Backend _backend;
  final void Function(BrowserError error) _onError;
  final void Function(int tabId)? _onTabChanged;
  late final TabStore<List<CapturedRequest>> _store;

  final List<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>[];

  /// Serialises the event handling: two events must not lose each other's
  /// read-modify-write of the same tab state.
  Future<void> _work = Future<void>.value();

  bool _started = false;

  /// Subscribes to the three webRequest events.
  ///
  /// In a service worker, call this synchronously during start-up, or the
  /// event that woke the worker is lost. Fails with [InvalidArgument] for a
  /// second call or a non-positive [maxRequestsPerTab], and passes through
  /// whatever the registration reports -- most plainly [NotAvailable] when
  /// the manifest lacks the `webRequest` permission.
  Result<void, BrowserError> start() {
    if (_started) {
      return const Err(InvalidArgument('the capture is already started'));
    }
    if (maxRequestsPerTab < 1) {
      return Err(InvalidArgument(
          'maxRequestsPerTab must be at least 1, got $maxRequestsPerTab'));
    }

    final webRequest = _backend.webRequest;
    final sent = webRequest.onSendHeaders();
    final received = webRequest.onHeadersReceived();
    final started = webRequest.onResponseStarted();
    // All three or none: a partial capture would pair nothing.
    switch ((sent, received, started)) {
      case (
          Ok<Stream<RequestHeadersSent>, BrowserError>(value: final sentStream),
          Ok<Stream<ResponseHeadersReceived>, BrowserError>(
            value: final receivedStream
          ),
          Ok<Stream<ResponseStarted>, BrowserError>(value: final startedStream)
        ):
        _subscriptions
          ..add(sentStream.listen((event) => _enqueue(() => _onSent(event))))
          ..add(receivedStream
              .listen((event) => _enqueue(() => _onReceived(event))))
          ..add(startedStream
              .listen((event) => _enqueue(() => _onStarted(event))));
        _started = true;
        return const Ok<void, BrowserError>(null);
      case (Err<Stream<RequestHeadersSent>, BrowserError>(:final error), _, _):
        return Err(error);
      case (
          _,
          Err<Stream<ResponseHeadersReceived>, BrowserError>(:final error),
          _
        ):
        return Err(error);
      case (_, _, Err<Stream<ResponseStarted>, BrowserError>(:final error)):
        return Err(error);
    }
  }

  /// The captured requests of [tabId], oldest first.
  ///
  /// A tab that was never captured is an [Ok] holding an empty list. After
  /// a worker restart the first read comes from storage, which is the
  /// point of the whole class. Fails with [InvalidArgument] for a negative
  /// [tabId], and passes through whatever storage reports.
  Future<Result<List<CapturedRequest>, BrowserError>> requestsForTab(
    int tabId,
  ) async {
    await _work;
    final read = await _store.read(tabId);
    return read.map((value) => value ?? const <CapturedRequest>[]);
  }

  /// Cancels the subscriptions, finishes pending writes and releases the
  /// store's cleanup subscription.
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _work;
    await _store.dispose();
  }

  void _enqueue(Future<void> Function() task) {
    _work = _work.then((_) => task());
  }

  Future<void> _onSent(RequestHeadersSent event) async {
    if (event.tabId < 0) {
      return;
    }
    final hop = RequestHop(
      url: event.url,
      method: event.method,
      requestHeaders: event.headers,
      sentAt: event.timeStamp,
      statusCode: null,
      responseHeaders: const <HttpHeader>[],
      receivedAt: null,
    );

    await _mutate(event.tabId, (requests) {
      final index = _indexOf(requests, event.requestId);
      if (index >= 0) {
        // Another send under a known request id is the next hop of its
        // chain (measured: one id across all hops, ADR-005).
        final entry = requests[index];
        requests[index] = _withHops(entry, [...entry.hops, hop]);
        return requests;
      }

      if (event.resourceType == 'main_frame') {
        // A new main document request is a navigation: the specification
        // drops captured state when the tab navigates, so the capture
        // starts over.
        requests.clear();
      }

      if (requests.length >= maxRequestsPerTab) {
        final evictable =
            requests.indexWhere((request) => !request.isMainFrame);
        if (evictable < 0) {
          // Nothing may be evicted (only main document entries left, which
          // are never evicted); the newcomer is dropped instead.
          return requests;
        }
        requests.removeAt(evictable);
      }

      requests.add(CapturedRequest(
        requestId: event.requestId,
        tabId: event.tabId,
        resourceType: event.resourceType,
        hops: List<RequestHop>.unmodifiable([hop]),
        finalStatusCode: null,
        ip: null,
        fromCache: null,
        startedAt: null,
      ));
      return requests;
    });
  }

  Future<void> _onReceived(ResponseHeadersReceived event) async {
    if (event.tabId < 0) {
      return;
    }
    await _mutate(event.tabId, (requests) {
      final index = _indexOf(requests, event.requestId);
      if (index < 0) {
        return null; // Capture begins at the send; see the class comment.
      }
      final entry = requests[index];
      final lastHop = entry.hops.last;
      final answered = RequestHop(
        url: lastHop.url,
        method: lastHop.method,
        requestHeaders: lastHop.requestHeaders,
        sentAt: lastHop.sentAt,
        statusCode: event.statusCode,
        responseHeaders: event.headers,
        receivedAt: event.timeStamp,
      );
      requests[index] = _withHops(
          entry, [...entry.hops.take(entry.hops.length - 1), answered]);
      return requests;
    });
  }

  Future<void> _onStarted(ResponseStarted event) async {
    if (event.tabId < 0) {
      return;
    }
    await _mutate(event.tabId, (requests) {
      final index = _indexOf(requests, event.requestId);
      if (index < 0) {
        return null; // Capture begins at the send; see the class comment.
      }
      final entry = requests[index];
      requests[index] = CapturedRequest(
        requestId: entry.requestId,
        tabId: entry.tabId,
        resourceType: entry.resourceType,
        hops: entry.hops,
        finalStatusCode: event.statusCode,
        ip: event.ip,
        fromCache: event.fromCache,
        startedAt: event.timeStamp,
      );
      return requests;
    });
  }

  /// Reads the state of [tabId], applies [change], writes the result back.
  ///
  /// [change] returns null to signal "nothing to write". Failures of read
  /// and write go to the error callback; the event is then dropped, which
  /// is visible in the report the callback feeds rather than silent.
  Future<void> _mutate(
    int tabId,
    List<CapturedRequest>? Function(List<CapturedRequest> requests) change,
  ) async {
    final read = await _store.read(tabId);
    final List<CapturedRequest> requests;
    switch (read) {
      case Ok<List<CapturedRequest>?, BrowserError>(:final value):
        requests = List<CapturedRequest>.of(value ?? const <CapturedRequest>[]);
      case Err<List<CapturedRequest>?, BrowserError>(:final error):
        _onError(error);
        return;
    }
    final changed = change(requests);
    if (changed == null) {
      return;
    }
    final written = await _store.write(tabId, changed);
    switch (written) {
      case Ok<void, BrowserError>():
        _onTabChanged?.call(tabId);
      case Err<void, BrowserError>(:final error):
        _onError(error);
    }
  }

  static int _indexOf(List<CapturedRequest> requests, String requestId) =>
      requests.indexWhere((request) => request.requestId == requestId);

  static CapturedRequest _withHops(
    CapturedRequest entry,
    List<RequestHop> hops,
  ) =>
      CapturedRequest(
        requestId: entry.requestId,
        tabId: entry.tabId,
        resourceType: entry.resourceType,
        hops: List<RequestHop>.unmodifiable(hops),
        finalStatusCode: entry.finalStatusCode,
        ip: entry.ip,
        fromCache: entry.fromCache,
        startedAt: entry.startedAt,
      );
}

Map<String, Object?> _encodeRequests(List<CapturedRequest> requests) =>
    <String, Object?>{
      'requests': <Object?>[
        for (final request in requests)
          <String, Object?>{
            'requestId': request.requestId,
            'tabId': request.tabId,
            'resourceType': request.resourceType,
            'finalStatusCode': request.finalStatusCode,
            'ip': request.ip,
            'fromCache': request.fromCache,
            'startedAt': request.startedAt,
            'hops': <Object?>[
              for (final hop in request.hops)
                <String, Object?>{
                  'url': hop.url,
                  'method': hop.method,
                  'sentAt': hop.sentAt,
                  'statusCode': hop.statusCode,
                  'receivedAt': hop.receivedAt,
                  'requestHeaders': _encodeHeaders(hop.requestHeaders),
                  'responseHeaders': _encodeHeaders(hop.responseHeaders),
                },
            ],
          },
      ],
    };

List<Object?> _encodeHeaders(List<HttpHeader> headers) => <Object?>[
      for (final header in headers)
        <String, Object?>{'name': header.name, 'value': header.value},
    ];

// The decode side reads defensively: after a real storage round trip
// NESTED maps arrive as whatever the interop layer produced (string-keyed
// only at the top level), so every inner map is re-narrowed instead of
// cast. A shape the codec cannot read throws, and the store turns that
// into an Unexpected -- the documented contract of TabStoreCodec.decode.

List<CapturedRequest> _decodeRequests(Map<String, Object?> json) =>
    List<CapturedRequest>.unmodifiable(
      (json['requests']! as List<Object?>).map((Object? raw) {
        final map = _asStringKeyedMap(raw);
        return CapturedRequest(
          requestId: map['requestId']! as String,
          tabId: (map['tabId']! as num).toInt(),
          resourceType: map['resourceType']! as String,
          finalStatusCode: (map['finalStatusCode'] as num?)?.toInt(),
          ip: map['ip'] as String?,
          fromCache: map['fromCache'] as bool?,
          startedAt: (map['startedAt'] as num?)?.toDouble(),
          hops: List<RequestHop>.unmodifiable(
            (map['hops']! as List<Object?>).map((Object? rawHop) {
              final hop = _asStringKeyedMap(rawHop);
              return RequestHop(
                url: hop['url']! as String,
                method: hop['method']! as String,
                sentAt: (hop['sentAt']! as num).toDouble(),
                statusCode: (hop['statusCode'] as num?)?.toInt(),
                receivedAt: (hop['receivedAt'] as num?)?.toDouble(),
                requestHeaders: _decodeHeaders(hop['requestHeaders']),
                responseHeaders: _decodeHeaders(hop['responseHeaders']),
              );
            }),
          ),
        );
      }),
    );

List<HttpHeader> _decodeHeaders(Object? raw) => List<HttpHeader>.unmodifiable(
      (raw! as List<Object?>).map((Object? entry) {
        final map = _asStringKeyedMap(entry);
        return HttpHeader(
          name: map['name']! as String,
          value: map['value']! as String,
        );
      }),
    );

Map<String, Object?> _asStringKeyedMap(Object? value) {
  final map = value! as Map<Object?, Object?>;
  return <String, Object?>{
    for (final entry in map.entries)
      if (entry.key case final String key) key: entry.value,
  };
}
