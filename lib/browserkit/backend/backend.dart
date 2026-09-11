// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The injectable boundary between this library and a browser.
///
/// Nothing in this file mentions a type from `package:chrome_extension`, and
/// that is the property everything else rests on: the facades above are
/// written against these interfaces, tests supply a plain-Dart
/// implementation, and a future Firefox backend is a third implementation
/// that changes nothing above it.
library;

import '../error.dart';
import '../result.dart';
import '../types.dart';

/// A browser, as far as this library is concerned.
///
/// One namespace per member -- eight of them -- and within each only the
/// calls a consumer needs. webRequest is
/// bound by hand-written interop rather than through the binding package,
/// whose outer layer cannot pass a filter or an extraInfoSpec; see ADR-004.
///
/// Implementations do not throw. Every failure arrives as an [Err] carrying a
/// [BrowserError], which is what lets the layers above be exhaustive about
/// failure instead of hopeful.
abstract interface class Backend {
  /// Messaging and extension lifecycle.
  RuntimeBackend get runtime;

  /// Tab lookup and tab lifetime events.
  TabsBackend get tabs;

  /// The `storage.session` area: browser memory, never written to disk,
  /// survives a service worker restart, cleared when the browser closes.
  StorageAreaBackend get sessionStorage;

  /// The `storage.sync` area: persisted, and shared across the devices of a
  /// profile where the browser offers it. The home of settings.
  StorageAreaBackend get syncStorage;

  /// The toolbar button: icon, title and badge.
  ActionBackend get action;

  /// Timers that survive a service worker restart.
  AlarmsBackend get alarms;

  /// Optional host permissions: query and request.
  PermissionsBackend get permissions;

  /// Programmatic script injection.
  ScriptingBackend get scripting;

  /// Request and response header capture.
  WebRequestBackend get webRequest;
}

/// Messaging and extension lifecycle.
abstract interface class RuntimeBackend {
  /// The identifier the browser assigned to this extension.
  Result<String, BrowserError> extensionId();

  /// Turns a path inside the extension package into an absolute URL.
  Result<String, BrowserError> urlForPath(String path);

  /// Opens the options page the manifest declares.
  Future<Result<void, BrowserError>> openOptionsPage();

  /// Sends [message] to the other parts of this extension and waits for the
  /// single reply.
  ///
  /// Messages are JSON objects. The browser permits any JSON value, but this
  /// library narrows it to an object so the type stays honest: a bare
  /// `Object` would push `dynamic` onto every consumer, which CLAUDE.md rule
  /// 5 forbids.
  Future<Result<Map<String, Object?>, BrowserError>> sendMessage(
    Map<String, Object?> message,
  );

  /// Messages sent to this extension by its other parts.
  ///
  /// The receiving half of [sendMessage]. Each event carries the payload and
  /// the reply channel; answering happens through [IncomingMessage.respond].
  /// While a subscription is active, every incoming message keeps its reply
  /// channel open until it is answered.
  ///
  /// A broadcast stream. Subscribing registers with the browser and
  /// cancelling deregisters, so the subscription is the unit of cleanup.
  Stream<IncomingMessage> get onMessage;

  /// Fires when the extension is installed or updated.
  ///
  /// A broadcast stream. Subscribing registers with the browser and
  /// cancelling deregisters, so the subscription is the unit of cleanup.
  Stream<ExtensionInstalled> get onInstalled;

  /// Fires when a profile with this extension installed is started.
  Stream<void> get onStartup;
}

/// Tab lookup and tab lifetime events.
abstract interface class TabsBackend {
  /// Returns the tabs matching [query].
  Future<Result<List<TabInfo>, BrowserError>> query(TabQuery query);

  /// Fires when a tab is closed.
  ///
  /// The event that drives per-tab cleanup. A store keyed by tab identifier
  /// that does not listen here leaks an entry per closed tab, and the leak is
  /// invisible until the storage quota is reached.
  Stream<TabRemoved> get onRemoved;

  /// Fires when one tab takes the place of another.
  ///
  /// Not a close followed by an open: no [onRemoved] arrives for the replaced
  /// tab, so a listener that only watches removals silently keeps state under
  /// an identifier nothing will ever ask about again.
  Stream<TabReplaced> get onReplaced;
}

/// One key-value storage area, addressed by key.
///
/// The same shape serves `storage.session` and `storage.sync`; which
/// lifetime a value gets is decided by which area the caller writes to, not
/// by how it writes. Values are JSON objects. Serialising a caller type into
/// one is the caller's job; this interface does not know what it holds.
abstract interface class StorageAreaBackend {
  /// Reads the value stored under [key], or null when there is none.
  ///
  /// A missing key is an [Ok] holding null, not an [Err]. After a service
  /// worker restart the first read of a live tab legitimately finds nothing,
  /// and that is not a failure.
  Future<Result<Map<String, Object?>?, BrowserError>> read(String key);

  /// Stores [value] under [key], replacing whatever was there.
  Future<Result<void, BrowserError>> write(
    String key,
    Map<String, Object?> value,
  );

  /// Removes [key]. Removing a key that is not there succeeds.
  Future<Result<void, BrowserError>> remove(String key);
}

/// The toolbar button: icon, title and badge, each settable per tab.
///
/// A value set with a tab identifier applies while that tab is selected and
/// is dropped by the browser when the tab closes; a value set without one is
/// the default for every tab that has no own value.
abstract interface class ActionBackend {
  /// Points the icon at packaged image files, keyed by pixel size.
  Future<Result<void, BrowserError>> setIcon(
    Map<String, String> pathBySize, {
    int? tabId,
  });

  /// Sets the tooltip text.
  Future<Result<void, BrowserError>> setTitle(String title, {int? tabId});

  /// Sets the badge text. An empty string removes the badge.
  Future<Result<void, BrowserError>> setBadgeText(String text, {int? tabId});

  /// Sets the badge background to a CSS color value.
  Future<Result<void, BrowserError>> setBadgeBackgroundColor(
    String cssColor, {
    int? tabId,
  });
}

/// Timers that survive a service worker restart.
abstract interface class AlarmsBackend {
  /// Creates or replaces the alarm called [name].
  ///
  /// [delayInMinutes] schedules the first firing, [periodInMinutes] every
  /// further one. The browser persists the alarm, so it fires even when the
  /// worker that created it is long gone.
  Future<Result<void, BrowserError>> create(
    String name, {
    double? delayInMinutes,
    double? periodInMinutes,
  });

  /// Clears the alarm called [name].
  ///
  /// The value reports whether an alarm of that name existed. Clearing a
  /// name that does not is an [Ok] holding false, not an [Err].
  Future<Result<bool, BrowserError>> clear(String name);

  /// Fires when an alarm goes off.
  ///
  /// A broadcast stream. Subscribing registers with the browser and
  /// cancelling deregisters, so the subscription is the unit of cleanup.
  Stream<AlarmFired> get onAlarm;
}

/// Optional host permissions: query and request.
abstract interface class PermissionsBackend {
  /// Whether the extension currently holds every origin in [origins].
  Future<Result<bool, BrowserError>> containsHosts(List<String> origins);

  /// Asks the user to grant the origins in [origins].
  ///
  /// The value reports whether the user granted them. May only be called
  /// from a user gesture; outside of one the browser refuses.
  Future<Result<bool, BrowserError>> requestHosts(List<String> origins);
}

/// Request and response header capture.
///
/// Unlike the other event surfaces these are methods returning a [Result],
/// not bare stream getters: registration here is parameterised (the filter
/// and the extraInfoSpec, fixed by the implementation) and can fail, most
/// plainly with [NotAvailable] when the manifest lacks the `webRequest`
/// permission -- and a failure must arrive as a value. See ADR-004.
abstract interface class WebRequestBackend {
  /// The stream of outgoing requests, headers included.
  ///
  /// Observed are http and https requests the extension may see. Each
  /// returned stream is broadcast; subscribing registers with the browser
  /// and cancelling deregisters, so the subscription is the unit of
  /// cleanup.
  Result<Stream<RequestHeadersSent>, BrowserError> onSendHeaders();

  /// The stream of arrived response header blocks, one per hop.
  ///
  /// Same scope and same subscription rules as [onSendHeaders].
  Result<Stream<ResponseHeadersReceived>, BrowserError> onHeadersReceived();

  /// The stream of final responses: first byte available, once per request.
  ///
  /// Same scope and same subscription rules as [onSendHeaders].
  Result<Stream<ResponseStarted>, BrowserError> onResponseStarted();
}

/// Programmatic script injection.
abstract interface class ScriptingBackend {
  /// Runs the packaged script [files] in the tab with [tabId].
  ///
  /// The scripts' return values are deliberately not transported: they
  /// arrive from the browser untyped, and no consumer of THIS call
  /// needs them.
  Future<Result<void, BrowserError>> executeScriptFiles({
    required int tabId,
    required List<String> files,
  });

  /// Runs the packaged script [files] in the tab with [tabId] and
  /// returns the top frame's completion value as a string.
  ///
  /// The transport is deliberately this narrow: exactly one string, or
  /// null when the browser reports no result or a non-string one --
  /// richer results wait for a consumer.
  Future<Result<String?, BrowserError>> executeScriptFilesForString({
    required int tabId,
    required List<String> files,
  });
}
