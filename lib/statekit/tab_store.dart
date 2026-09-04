// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Per-tab state that survives a service worker restart.
///
/// This is the reason the library exists. It started inside `browserkit`
/// and moved here when `netkit` became the second inhabitant of
/// restart-surviving state -- the trigger the placement decision named:
/// a second consumer, not a first.
library;

import 'dart:async';

import '../browserkit/backend/backend.dart';
import '../browserkit/error.dart';
import '../browserkit/result.dart';

/// Converts a stored type to a JSON object and back.
///
/// Supplied by the caller, because the store does not know what it holds.
final class TabStoreCodec<T> {
  /// Pairs an [encode] function with its [decode] counterpart.
  const TabStoreCodec({required this.encode, required this.decode});

  /// Turns a value into the JSON object that is stored.
  final Map<String, Object?> Function(T value) encode;

  /// Rebuilds a value from a stored JSON object.
  ///
  /// May throw. A stored object can predate the current version of the
  /// extension, and the store turns a throw here into an [Unexpected] rather
  /// than letting it escape.
  final T Function(Map<String, Object?> json) decode;
}

/// State keyed by tab identifier, backed by `storage.session`.
///
/// The Manifest V3 background context is a service worker. The browser
/// terminates it after roughly thirty seconds of inactivity and restarts it
/// on the next event, and every in-memory value is lost across that boundary.
/// On a normal browsing session that happens dozens of times per hour, so a
/// plain map is not a simplification of this class, it is a defect that only
/// shows up when nobody is watching.
///
/// `storage.session` lives in browser memory, is never written to disk,
/// survives a worker restart and is cleared when the browser closes, which is
/// exactly the lifetime per-tab state wants. An in-memory cache sits in front
/// of it so repeated reads within one worker lifetime cost nothing.
///
/// Three properties are worth knowing before relying on it:
///
/// **Writes go through immediately.** No batching, no debouncing. The worker
/// can be terminated between an event and a delayed write, and a lost write
/// is indistinguishable from a bug.
///
/// **A read can legitimately find nothing.** After a restart the cache is
/// cold and the first read goes to storage, which may hold no entry. That is
/// `Ok(null)`, not an error.
///
/// **Size is the caller's problem.** `storage.session` has a quota, and an
/// unbounded per-tab value will reach it.
///
/// The store clears its own entry when a tab closes, so consumers do not have
/// to remember to. It does **not** react to tab replacement: see
/// `TabsApi.onReplaced` for why that event needs handling and what happens if
/// it is ignored.
final class TabStore<T> {
  /// Creates a store over [backend], keeping its entries under [namespace].
  ///
  /// [namespace] separates one store from another in the shared session area;
  /// two stores with the same namespace would overwrite each other. [codec]
  /// says how a value becomes a JSON object.
  ///
  /// [onCleanupError] receives the failures of the automatic cleanup that
  /// runs when a tab closes. It is required rather than optional on purpose:
  /// that cleanup has no caller to return a [Result] to, so without it the
  /// only remaining option would be to discard the error silently.
  ///
  /// The constructor subscribes to tab removal. Call [dispose] to release
  /// that subscription.
  TabStore({
    required Backend backend,
    required String namespace,
    required TabStoreCodec<T> codec,
    required void Function(BrowserError error) onCleanupError,
  })  : _storage = backend.sessionStorage,
        _namespace = namespace,
        _codec = codec,
        _onCleanupError = onCleanupError {
    _removals = backend.tabs.onRemoved.listen((event) {
      unawaited(_clearAfterClose(event.tabId));
    });
  }

  final StorageAreaBackend _storage;
  final String _namespace;
  final TabStoreCodec<T> _codec;
  final void Function(BrowserError error) _onCleanupError;
  final Map<int, T> _cache = <int, T>{};

  late final StreamSubscription<void> _removals;

  /// Reads the value stored for [tabId], or null when there is none.
  ///
  /// Served from the cache when possible. A cache miss goes to storage and,
  /// on success, fills the cache.
  ///
  /// Only present values are cached. An absent one is looked up again next
  /// time, which costs a storage read and buys correctness: another extension
  /// context may have written the entry in the meantime, and a cached absence
  /// would hide it. The same reasoning does not rescue a cached present
  /// value, which another context can still make stale; that is the accepted
  /// price of having a cache at all.
  ///
  /// Fails with [InvalidArgument] for a negative [tabId], and passes through
  /// whatever the storage area reports. A stored object the codec cannot read
  /// becomes [Unexpected] rather than a throw.
  Future<Result<T?, BrowserError>> read(int tabId) async {
    final rejected = _rejectInvalid<T?>(tabId);
    if (rejected != null) {
      return rejected;
    }

    final cached = _cache[tabId];
    if (cached != null) {
      return Ok<T?, BrowserError>(cached);
    }

    final stored = await _storage.read(_keyFor(tabId));
    switch (stored) {
      case Err<Map<String, Object?>?, BrowserError>(:final error):
        return Err<T?, BrowserError>(error);
      case Ok<Map<String, Object?>?, BrowserError>(:final value):
        if (value == null) {
          return Ok<T?, BrowserError>(null);
        }
        final T decoded;
        try {
          decoded = _codec.decode(value);
        } on Object catch (thrown) {
          return Err<T?, BrowserError>(
            Unexpected(
              'stored value for tab $tabId could not be decoded',
              cause: thrown,
            ),
          );
        }
        _cache[tabId] = decoded;
        return Ok<T?, BrowserError>(decoded);
    }
  }

  /// Stores [value] for [tabId], replacing whatever was there.
  ///
  /// Storage is written first and the cache updated only after it succeeded,
  /// so the cache never claims something the store does not hold. If the
  /// write fails, the cached entry is dropped instead of kept: what storage
  /// holds is then unknown, and an unknown value must not be served from
  /// memory as though it were confirmed.
  ///
  /// Fails with [InvalidArgument] for a negative [tabId], and passes through
  /// whatever the storage area reports.
  Future<Result<void, BrowserError>> write(int tabId, T value) async {
    final rejected = _rejectInvalid<void>(tabId);
    if (rejected != null) {
      return rejected;
    }

    final written = await _storage.write(_keyFor(tabId), _codec.encode(value));
    switch (written) {
      case Err<void, BrowserError>(:final error):
        _cache.remove(tabId);
        return Err<void, BrowserError>(error);
      case Ok<void, BrowserError>():
        _cache[tabId] = value;
        return const Ok<void, BrowserError>(null);
    }
  }

  /// Removes the entry for [tabId].
  ///
  /// Clearing an entry that is not there succeeds. The cached entry is
  /// dropped either way: after a failed removal storage may or may not still
  /// hold the value, and serving the old one from memory would be a guess.
  ///
  /// Fails with [InvalidArgument] for a negative [tabId], and passes through
  /// whatever the storage area reports.
  Future<Result<void, BrowserError>> clear(int tabId) async {
    final rejected = _rejectInvalid<void>(tabId);
    if (rejected != null) {
      return rejected;
    }

    _cache.remove(tabId);
    return _storage.remove(_keyFor(tabId));
  }

  /// Releases the tab removal subscription.
  ///
  /// After this the store no longer cleans up after closed tabs. Reads and
  /// writes keep working, so a store that is disposed but still used will
  /// accumulate entries.
  Future<void> dispose() => _removals.cancel();

  /// The number of entries currently held in memory.
  ///
  /// For tests and diagnostics. It says nothing about what storage holds.
  int get cachedEntryCount => _cache.length;

  /// Clears the entry of a tab that has just closed, reporting a failure to
  /// the cleanup callback, because there is no caller to return it to.
  Future<void> _clearAfterClose(int tabId) async {
    final cleared = await clear(tabId);
    if (cleared case Err<void, BrowserError>(:final error)) {
      _onCleanupError(error);
    }
  }

  /// Returns an [Err] when [tabId] cannot name a tab, and null otherwise.
  ///
  /// A negative identifier is a caller bug, not a browser condition: the
  /// browser uses -1 to mean no tab at all, and storing against it would
  /// collect state nothing can ever read back.
  Result<R, BrowserError>? _rejectInvalid<R>(int tabId) => tabId < 0
      ? Err<R, BrowserError>(InvalidArgument('tab id must not be negative, '
          'got $tabId'))
      : null;

  /// The storage key for [tabId] within this namespace.
  String _keyFor(int tabId) => '$_namespace/$tabId';
}
