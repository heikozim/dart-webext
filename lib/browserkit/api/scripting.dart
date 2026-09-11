// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `scripting` facade: programmatic injection.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';

/// Programmatic script injection.
///
/// Follows the facade pattern documented on `RuntimeApi`. Two calls, one
/// with and one without a transported result, because that is the
/// namespace's agreed purpose; CSS
/// injection and registered content scripts wait for a consumer.
final class ScriptingApi {
  /// Binds the facade to the given [Backend].
  const ScriptingApi(this._backend);

  final Backend _backend;

  /// Runs the packaged script [files], in order, in the tab with [tabId].
  ///
  /// Paths are relative to the extension package root. Injection needs a
  /// host permission for the page shown in that tab; without one the
  /// browser refuses and the refusal arrives as an [Err], typically
  /// [PermissionDenied].
  ///
  /// The scripts' return values are deliberately not transported: they
  /// arrive from the browser untyped, and no consumer needs them yet.
  ///
  /// A negative [tabId], an empty [files] list and an empty entry are
  /// rejected with [InvalidArgument] without consulting the browser.
  Future<Result<void, BrowserError>> executeScriptFiles({
    required int tabId,
    required List<String> files,
  }) {
    final rejection = _rejectionFor(tabId: tabId, files: files);
    if (rejection != null) {
      return _invalid(rejection);
    }
    return _backend.scripting.executeScriptFiles(tabId: tabId, files: files);
  }

  /// Runs the packaged script [files], in order, in the tab with [tabId]
  /// and returns the top frame's completion value as a string.
  ///
  /// Same permission requirements and argument checks as
  /// [executeScriptFiles]. The transport is deliberately narrow: exactly
  /// one string, or null when the browser reports no result or a
  /// non-string one -- the caller treats null as "not measurable", never
  /// as an error.
  Future<Result<String?, BrowserError>> executeScriptFilesForString({
    required int tabId,
    required List<String> files,
  }) {
    final rejection = _rejectionFor(tabId: tabId, files: files);
    if (rejection != null) {
      return Future<Result<String?, BrowserError>>.value(
        Err<String?, BrowserError>(InvalidArgument(rejection)),
      );
    }
    return _backend.scripting
        .executeScriptFilesForString(tabId: tabId, files: files);
  }

  static String? _rejectionFor({
    required int tabId,
    required List<String> files,
  }) {
    if (tabId < 0) {
      return 'tab id must not be negative, got $tabId';
    }
    if (files.isEmpty) {
      return 'at least one script file is required';
    }
    if (files.any((file) => file.isEmpty)) {
      return 'script files must not contain an empty entry';
    }
    return null;
  }

  Future<Result<void, BrowserError>> _invalid(String detail) =>
      Future<Result<void, BrowserError>>.value(
        Err<void, BrowserError>(InvalidArgument(detail)),
      );
}
