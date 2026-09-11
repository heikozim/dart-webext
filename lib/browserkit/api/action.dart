// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `action` facade: the toolbar button.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';

/// The toolbar button: icon, title and badge, each settable per tab.
///
/// Follows the facade pattern documented on `RuntimeApi`.
///
/// A value set with [ActionApi.setIcon]'s `tabId` (and the same for the
/// other calls) applies while that tab is selected and is dropped by the
/// browser when the tab closes; a value set without a tab identifier is the
/// default for every tab without an own value. Per-tab values need no
/// cleanup, which is the property that makes the button cheap to drive from
/// per-tab events.
final class ActionApi {
  /// Binds the facade to the given [Backend].
  const ActionApi(this._backend);

  final Backend _backend;

  /// Points the icon at packaged image files, keyed by pixel size.
  ///
  /// [pathBySize] maps a pixel size to a path inside the extension package,
  /// for example `{'16': 'icons/orange-16.png', '32': 'icons/orange-32.png'}`.
  /// The browser picks the entry matching the screen density. An empty map
  /// and a negative [tabId] are rejected with [InvalidArgument] without
  /// consulting the browser.
  Future<Result<void, BrowserError>> setIcon(
    Map<String, String> pathBySize, {
    int? tabId,
  }) {
    if (pathBySize.isEmpty) {
      return _invalid('at least one icon path is required');
    }
    final rejected = _rejectInvalidTab(tabId);
    if (rejected != null) {
      return rejected;
    }
    return _backend.action.setIcon(pathBySize, tabId: tabId);
  }

  /// Sets the tooltip text.
  ///
  /// A negative [tabId] is rejected with [InvalidArgument] without
  /// consulting the browser.
  Future<Result<void, BrowserError>> setTitle(String title, {int? tabId}) {
    final rejected = _rejectInvalidTab(tabId);
    if (rejected != null) {
      return rejected;
    }
    return _backend.action.setTitle(title, tabId: tabId);
  }

  /// Sets the badge text. An empty string removes the badge.
  ///
  /// About four characters fit; the browser truncates longer text rather
  /// than failing. A negative [tabId] is rejected with [InvalidArgument]
  /// without consulting the browser.
  Future<Result<void, BrowserError>> setBadgeText(String text, {int? tabId}) {
    final rejected = _rejectInvalidTab(tabId);
    if (rejected != null) {
      return rejected;
    }
    return _backend.action.setBadgeText(text, tabId: tabId);
  }

  /// Sets the badge background to a CSS color value.
  ///
  /// An empty color and a negative [tabId] are rejected with
  /// [InvalidArgument] without consulting the browser.
  Future<Result<void, BrowserError>> setBadgeBackgroundColor(
    String cssColor, {
    int? tabId,
  }) {
    if (cssColor.isEmpty) {
      return _invalid('the badge color must not be empty');
    }
    final rejected = _rejectInvalidTab(tabId);
    if (rejected != null) {
      return rejected;
    }
    return _backend.action.setBadgeBackgroundColor(cssColor, tabId: tabId);
  }

  /// Returns an [Err] future for a negative [tabId], and null otherwise.
  ///
  /// The browser uses -1 to mean no tab at all; targeting it would set a
  /// value nothing can ever show.
  Future<Result<void, BrowserError>>? _rejectInvalidTab(int? tabId) =>
      tabId != null && tabId < 0
          ? _invalid('tab id must not be negative, got $tabId')
          : null;

  Future<Result<void, BrowserError>> _invalid(String detail) =>
      Future<Result<void, BrowserError>>.value(
        Err<void, BrowserError>(InvalidArgument(detail)),
      );
}
