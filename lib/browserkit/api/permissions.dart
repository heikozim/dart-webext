// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `permissions` facade: optional host permissions.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';

/// Optional host permissions: query and request.
///
/// Follows the facade pattern documented on `RuntimeApi`. The scope is
/// deliberately narrow: host permissions only. Named
/// API permissions are requested in the manifest, where the reviewer sees
/// them; requesting them at runtime is not offered here until a consumer
/// needs it.
final class PermissionsApi {
  /// Binds the facade to the given [Backend].
  const PermissionsApi(this._backend);

  final Backend _backend;

  /// Whether the extension currently holds every origin in [origins].
  ///
  /// Origins are match patterns such as `https://example.org/*`. An empty
  /// list and an empty entry are rejected with [InvalidArgument] without
  /// consulting the browser: asking for nothing would answer true and read
  /// like a grant.
  Future<Result<bool, BrowserError>> containsHosts(List<String> origins) {
    final rejected = _rejectInvalid(origins);
    if (rejected != null) {
      return rejected;
    }
    return _backend.permissions.containsHosts(origins);
  }

  /// Asks the user to grant the origins in [origins].
  ///
  /// The value reports the user's decision: false is a refusal, not an
  /// error. The browser only shows the prompt from a user gesture, such as
  /// a click in the popup; called outside of one it refuses, and that
  /// refusal arrives as an [Err].
  ///
  /// An empty list and an empty entry are rejected with [InvalidArgument]
  /// without consulting the browser.
  Future<Result<bool, BrowserError>> requestHosts(List<String> origins) {
    final rejected = _rejectInvalid(origins);
    if (rejected != null) {
      return rejected;
    }
    return _backend.permissions.requestHosts(origins);
  }

  /// Returns an [Err] future for an unusable [origins] list, null otherwise.
  Future<Result<bool, BrowserError>>? _rejectInvalid(List<String> origins) {
    if (origins.isEmpty) {
      return _invalid('at least one origin is required');
    }
    if (origins.any((origin) => origin.isEmpty)) {
      return _invalid('origins must not contain an empty entry');
    }
    return null;
  }

  Future<Result<bool, BrowserError>> _invalid(String detail) =>
      Future<Result<bool, BrowserError>>.value(
        Err<bool, BrowserError>(InvalidArgument(detail)),
      );
}
