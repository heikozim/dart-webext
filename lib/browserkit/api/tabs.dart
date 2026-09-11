// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `tabs` facade: tab lookup and tab lifetime events.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';
import '../types.dart';

/// Tab lookup and tab lifetime events.
///
/// The second of the two reference facades. The pattern it follows is
/// documented on `RuntimeApi`; what this one adds is the treatment of events,
/// which are the harder half.
///
/// The scope for this namespace is query, removal and replacement. Reading or changing a single
/// tab is not here, because no consumer needs it yet.
final class TabsApi {
  /// Binds the facade to the given [Backend].
  const TabsApi(this._backend);

  final Backend _backend;

  /// Returns the tabs matching [query], in the order the browser reports.
  ///
  /// An empty query matches every tab. No match is an empty list and an
  /// [Ok]; only a browser refusal is an [Err].
  ///
  /// A tab whose address the extension may not read comes back with
  /// [TabInfo.url] null rather than being omitted. That is a permission
  /// statement about one tab, not a failure of the call, and treating it as
  /// an error would make a missing host permission look like a broken query.
  ///
  /// Fails with [NotAvailable] when there is no tabs namespace, and with
  /// [PermissionDenied] when the extension may not enumerate tabs at all.
  Future<Result<List<TabInfo>, BrowserError>> query(TabQuery query) =>
      _backend.tabs.query(query);

  /// Fires when a tab is closed.
  ///
  /// This is the event per-tab state has to listen to. Anything keyed by tab
  /// identifier that does not clean up here grows by one entry per closed
  /// tab, and nothing reports the growth until the storage quota is reached.
  ///
  /// Closing a window delivers one event per tab in it, each with
  /// [TabRemoved.isWindowClosing] set. Expect a burst, not a single event.
  ///
  /// A broadcast stream; the caller owns and cancels the subscription.
  Stream<TabRemoved> get onRemoved => _backend.tabs.onRemoved;

  /// Fires when one tab takes the place of another, keeping its position.
  ///
  /// Happens on prerendering and instant navigation. It is not a close
  /// followed by an open: **no [onRemoved] arrives for the replaced tab.** A
  /// listener that watches only removals therefore keeps state under an
  /// identifier that nothing will ask about again, while the user sees what
  /// looks like the same tab carrying none of it.
  ///
  /// Either move the state from [TabReplaced.removedTabId] to
  /// [TabReplaced.addedTabId], or drop it. Ignoring the event is the one
  /// option that is always wrong.
  ///
  /// A broadcast stream; the caller owns and cancels the subscription.
  Stream<TabReplaced> get onReplaced => _backend.tabs.onReplaced;
}
