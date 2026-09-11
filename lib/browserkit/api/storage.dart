// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `storage` facade: the session and sync key-value areas.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';

/// The two storage areas this library exposes.
///
/// Follows the facade pattern documented on `RuntimeApi`. The areas share
/// one shape and differ only in lifetime:
///
/// * [session] lives in browser memory, survives a service worker restart
///   and is cleared when the browser closes. Per-tab state belongs here,
///   usually through `TabStore` rather than through this facade directly.
/// * [sync] is persisted, and shared across the devices of a profile where
///   the browser offers it. Settings belong here.
final class StorageApi {
  /// Binds the facade to the given [Backend].
  const StorageApi(this._backend);

  final Backend _backend;

  /// The `storage.session` area.
  StorageAreaApi get session => StorageAreaApi._(_backend.sessionStorage);

  /// The `storage.sync` area.
  StorageAreaApi get sync => StorageAreaApi._(_backend.syncStorage);
}

/// One key-value area, addressed by key, holding JSON objects.
///
/// Serialising a caller type into a JSON object is the caller's job; the
/// area does not know what it holds.
final class StorageAreaApi {
  const StorageAreaApi._(this._area);

  final StorageAreaBackend _area;

  /// Reads the value stored under [key], or null when there is none.
  ///
  /// A missing key is an [Ok] holding null, not an [Err]. An empty key is
  /// rejected with [InvalidArgument] without consulting the browser.
  Future<Result<Map<String, Object?>?, BrowserError>> read(String key) {
    final rejected = _rejectEmptyKey<Map<String, Object?>?>(key);
    if (rejected != null) {
      return Future<Result<Map<String, Object?>?, BrowserError>>.value(
        rejected,
      );
    }
    return _area.read(key);
  }

  /// Stores [value] under [key], replacing whatever was there.
  ///
  /// An empty key is rejected with [InvalidArgument] without consulting the
  /// browser. Size is the caller's problem: every area has a quota, and an
  /// oversized write comes back as whatever the browser reports, wrapped in
  /// an [Err].
  Future<Result<void, BrowserError>> write(
    String key,
    Map<String, Object?> value,
  ) {
    final rejected = _rejectEmptyKey<void>(key);
    if (rejected != null) {
      return Future<Result<void, BrowserError>>.value(rejected);
    }
    return _area.write(key, value);
  }

  /// Removes [key]. Removing a key that is not there succeeds.
  ///
  /// An empty key is rejected with [InvalidArgument] without consulting the
  /// browser.
  Future<Result<void, BrowserError>> remove(String key) {
    final rejected = _rejectEmptyKey<void>(key);
    if (rejected != null) {
      return Future<Result<void, BrowserError>>.value(rejected);
    }
    return _area.remove(key);
  }

  /// Returns an [Err] for an empty [key], and null otherwise.
  ///
  /// An empty key is a caller bug: the browser would accept it, and the
  /// value would then hide under a name nothing searches for.
  Result<R, BrowserError>? _rejectEmptyKey<R>(String key) => key.isEmpty
      ? const Err(InvalidArgument('storage key must not be empty'))
      : null;
}
