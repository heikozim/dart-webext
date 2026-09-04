// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The production [Backend], and the only file in this library that imports
/// `package:chrome_extension`.
///
/// The import list below is the browser surface this library takes from the
/// binding package: seven of the eight namespaces this library binds.
/// The eighth, webRequest, is bound by hand at the end
/// of this file, because the package registers its listeners without a
/// filter and without an extraInfoSpec, so headers can never arrive through
/// its outer layer; see ADR-004. Adding an import is visible in a diff of
/// this list, which is the cheapest possible check that the seam has not
/// widened by accident.
///
/// This file only loads in a browser. Tests use `backend_fake.dart` and must
/// not import this one: `package:chrome_extension` reaches `dart:js_util`,
/// which does not exist on the Dart VM.
library;

import 'dart:async';
// The one deliberate exception to "no raw interop" (ADR-001, amended):
// replying to an incoming message means calling the raw JSFunction the
// package hands out as OnMessageEvent.sendResponse, and that takes
// dart:js_interop. It is confined to this file, like everything else the
// seam exists to confine.
import 'dart:js_interop';

import 'package:chrome_extension/action.dart' as chrome_action;
import 'package:chrome_extension/alarms.dart' as chrome_alarms;
import 'package:chrome_extension/permissions.dart' as chrome_permissions;
import 'package:chrome_extension/runtime.dart' as chrome_runtime;
import 'package:chrome_extension/scripting.dart' as chrome_scripting;
import 'package:chrome_extension/storage.dart' as chrome_storage;
import 'package:chrome_extension/tabs.dart' as chrome_tabs;

import '../error.dart';
import '../result.dart';
import '../types.dart';
import 'backend.dart';

/// Chrome, behind the [Backend] interface.
final class ChromeBackend implements Backend {
  /// Binds to the `chrome` object of the surrounding extension context.
  ChromeBackend();

  @override
  final RuntimeBackend runtime = const _ChromeRuntimeBackend();

  @override
  final TabsBackend tabs = const _ChromeTabsBackend();

  @override
  final StorageAreaBackend sessionStorage =
      const _ChromeStorageAreaBackend(_StorageArea.session);

  @override
  final StorageAreaBackend syncStorage =
      const _ChromeStorageAreaBackend(_StorageArea.sync);

  @override
  final ActionBackend action = const _ChromeActionBackend();

  @override
  final AlarmsBackend alarms = const _ChromeAlarmsBackend();

  @override
  final PermissionsBackend permissions = const _ChromePermissionsBackend();

  @override
  final ScriptingBackend scripting = const _ChromeScriptingBackend();

  @override
  final WebRequestBackend webRequest = const _ChromeWebRequestBackend();
}

/// Runs [body] and converts anything it throws into a [BrowserError].
///
/// [api] names the namespace, and [isAvailable] is its own report of whether
/// it exists. The availability check comes first because the exception the
/// package throws for an absent namespace is not exported and so cannot be
/// caught by type.
Result<T, BrowserError> _guard<T>(
  String api, {
  required bool isAvailable,
  required T Function() body,
}) {
  if (!isAvailable) {
    return Err<T, BrowserError>(NotAvailable(api));
  }
  try {
    return Ok<T, BrowserError>(body());
  } on Object catch (thrown) {
    return Err<T, BrowserError>(browserErrorFromThrown(thrown));
  }
}

/// The asynchronous form of [_guard].
Future<Result<T, BrowserError>> _guardAsync<T>(
  String api, {
  required bool isAvailable,
  required Future<T> Function() body,
}) async {
  if (!isAvailable) {
    return Err<T, BrowserError>(NotAvailable(api));
  }
  try {
    return Ok<T, BrowserError>(await body());
  } on Object catch (thrown) {
    return Err<T, BrowserError>(browserErrorFromThrown(thrown));
  }
}

/// Narrows an untyped value from the browser to a JSON object.
///
/// The package returns raw `Map` and `Object` from several calls, and those
/// types must not travel further; this is where they stop. Non-string keys
/// are dropped rather than coerced, because a JSON object cannot have them
/// and silently inventing one would hide a real mismatch.
Map<String, Object?> _asJsonObject(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final result = <String, Object?>{};
  for (final Object? key in value.keys) {
    if (key is String) {
      result[key] = value[key] as Object?;
    }
  }
  return Map<String, Object?>.unmodifiable(result);
}

/// Converts one browser tab into the library type.
TabInfo _toTabInfo(chrome_tabs.Tab tab) => TabInfo(
      id: tab.id,
      windowId: tab.windowId,
      index: tab.index,
      url: tab.url,
      title: tab.title,
      isActive: tab.active,
    );

/// Converts the browser install reason into the library enum.
///
/// An unrecognised value becomes [InstallReason.unknown] rather than throwing
/// or being dropped, so a new browser value cannot break an event listener.
InstallReason _toInstallReason(chrome_runtime.OnInstalledReason reason) =>
    switch (reason) {
      chrome_runtime.OnInstalledReason.install => InstallReason.install,
      chrome_runtime.OnInstalledReason.update => InstallReason.update,
      chrome_runtime.OnInstalledReason.chromeUpdate =>
        InstallReason.browserUpdate,
      chrome_runtime.OnInstalledReason.sharedModuleUpdate =>
        InstallReason.sharedModuleUpdate,
    };

/// Messaging and lifecycle, over `chrome.runtime`.
final class _ChromeRuntimeBackend implements RuntimeBackend {
  const _ChromeRuntimeBackend();

  static const String _api = 'chrome.runtime';

  bool get _isAvailable => chrome_runtime.chrome.runtime.isAvailable;

  @override
  Result<String, BrowserError> extensionId() => _guard<String>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_runtime.chrome.runtime.id,
      );

  @override
  Result<String, BrowserError> urlForPath(String path) {
    if (path.isEmpty) {
      return const Err<String, BrowserError>(
        InvalidArgument('path must not be empty'),
      );
    }
    return _guard<String>(
      _api,
      isAvailable: _isAvailable,
      body: () => chrome_runtime.chrome.runtime.getURL(path),
    );
  }

  @override
  Future<Result<void, BrowserError>> openOptionsPage() => _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_runtime.chrome.runtime.openOptionsPage(),
      );

  @override
  Future<Result<Map<String, Object?>, BrowserError>> sendMessage(
    Map<String, Object?> message,
  ) =>
      _guardAsync<Map<String, Object?>>(
        _api,
        isAvailable: _isAvailable,
        body: () async {
          final reply = await chrome_runtime.chrome.runtime.sendMessage(
            null,
            message,
            null,
          );
          return _asJsonObject(reply);
        },
      );

  @override
  Stream<IncomingMessage> get onMessage {
    // Not a plain .map over the package stream: the browser closes the reply
    // channel the moment the JavaScript listener returns, unless that
    // listener returns true. EventStream passes the Dart handler's return
    // value through to the JavaScript listener, which is what this relies
    // on -- and which .map would swallow.
    StreamSubscription<chrome_runtime.OnMessageEvent>? inner;
    // The controller is deliberately never closed: the stream is handed to
    // the caller, the unit of cleanup is the caller's subscription (onCancel
    // below releases the browser listener), and the controller holds no
    // resource beyond memory.
    // ignore: close_sinks
    late final StreamController<IncomingMessage> controller;
    controller = StreamController<IncomingMessage>.broadcast(
      onListen: () {
        inner = chrome_runtime.chrome.runtime.onMessage.listen((event) {
          final sendResponse = event.sendResponse;
          controller.add(
            IncomingMessage(
              payload: _asJsonObject(event.message),
              respond: (reply) {
                sendResponse.callAsFunction(null, reply.jsify());
              },
            ),
          );
          // Keeps the reply channel open until respond is called.
          return true;
        });
      },
      onCancel: () async {
        await inner?.cancel();
        inner = null;
      },
    );
    return controller.stream;
  }

  @override
  Stream<ExtensionInstalled> get onInstalled =>
      chrome_runtime.chrome.runtime.onInstalled.map(
        (details) => ExtensionInstalled(
          reason: _toInstallReason(details.reason),
          previousVersion: details.previousVersion,
        ),
      );

  @override
  Stream<void> get onStartup => chrome_runtime.chrome.runtime.onStartup;
}

/// Tab lookup and tab lifetime, over `chrome.tabs`.
final class _ChromeTabsBackend implements TabsBackend {
  const _ChromeTabsBackend();

  static const String _api = 'chrome.tabs';

  bool get _isAvailable => chrome_tabs.chrome.tabs.isAvailable;

  @override
  Future<Result<List<TabInfo>, BrowserError>> query(TabQuery query) =>
      _guardAsync<List<TabInfo>>(
        _api,
        isAvailable: _isAvailable,
        body: () async {
          final found = await chrome_tabs.chrome.tabs.query(
            chrome_tabs.QueryInfo(
              active: query.isActive,
              currentWindow: query.isInCurrentWindow,
              windowId: query.windowId,
            ),
          );
          return List<TabInfo>.unmodifiable(found.map(_toTabInfo));
        },
      );

  @override
  Stream<TabRemoved> get onRemoved => chrome_tabs.chrome.tabs.onRemoved.map(
        (event) => TabRemoved(
          tabId: event.tabId,
          windowId: event.removeInfo.windowId,
          isWindowClosing: event.removeInfo.isWindowClosing,
        ),
      );

  @override
  Stream<TabReplaced> get onReplaced => chrome_tabs.chrome.tabs.onReplaced.map(
        (event) => TabReplaced(
          addedTabId: event.addedTabId,
          removedTabId: event.removedTabId,
        ),
      );
}

/// Which storage area a [_ChromeStorageAreaBackend] speaks to.
///
/// An enum rather than a captured area object because the backends are
/// const, and `chrome.storage.session` is a runtime lookup.
enum _StorageArea { session, sync }

/// One key-value area, over `chrome.storage.session` or `chrome.storage.sync`.
final class _ChromeStorageAreaBackend implements StorageAreaBackend {
  const _ChromeStorageAreaBackend(this._area);

  final _StorageArea _area;

  static const String _api = 'chrome.storage';

  bool get _isAvailable => chrome_storage.chrome.storage.isAvailable;

  chrome_storage.StorageArea get _wrapped => switch (_area) {
        _StorageArea.session => chrome_storage.chrome.storage.session,
        _StorageArea.sync => chrome_storage.chrome.storage.sync,
      };

  @override
  Future<Result<Map<String, Object?>?, BrowserError>> read(String key) =>
      _guardAsync<Map<String, Object?>?>(
        _api,
        isAvailable: _isAvailable,
        body: () async {
          final area = await _wrapped.get(key);
          final stored = _asJsonObject(area)[key];
          // A key that was never written is absent, not an error: after a
          // service worker restart the first read of a live tab legitimately
          // finds nothing.
          return stored == null ? null : _asJsonObject(stored);
        },
      );

  @override
  Future<Result<void, BrowserError>> write(
    String key,
    Map<String, Object?> value,
  ) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => _wrapped.set(<String, Object?>{key: value}),
      );

  @override
  Future<Result<void, BrowserError>> remove(String key) => _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => _wrapped.remove(key),
      );
}

/// The toolbar button, over `chrome.action`.
final class _ChromeActionBackend implements ActionBackend {
  const _ChromeActionBackend();

  static const String _api = 'chrome.action';

  bool get _isAvailable => chrome_action.chrome.action.isAvailable;

  @override
  Future<Result<void, BrowserError>> setIcon(
    Map<String, String> pathBySize, {
    int? tabId,
  }) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () async {
          // The one action call bound by hand: the browser reports a
          // setIcon failure ONLY through runtime.lastError -- the promise
          // form resolves regardless, and an unread lastError lands as
          // "Unchecked runtime.lastError" in the extension's error list
          // (measured 2026-09-02: closing a tab mid-refresh produced one
          // per refresh, while the sibling setters rejected normally).
          // The callback form reads the error, and the read itself is
          // what silences the browser's complaint; the message then
          // travels the normal mapping, so a vanished tab arrives as
          // TabGone like everywhere else.
          final failure = Completer<String?>();
          _jsActionSetIconWithCallback(
            chrome_action.SetIconDetails(path: pathBySize, tabId: tabId).toJS,
            () {
              failure.complete(_jsRuntimeLastError?.message);
            }.toJS,
          );
          final message = await failure.future;
          if (message != null) {
            throw Exception(message);
          }
        },
      );

  @override
  Future<Result<void, BrowserError>> setTitle(String title, {int? tabId}) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_action.chrome.action.setTitle(
          chrome_action.SetTitleDetails(title: title, tabId: tabId),
        ),
      );

  @override
  Future<Result<void, BrowserError>> setBadgeText(String text, {int? tabId}) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_action.chrome.action.setBadgeText(
          chrome_action.SetBadgeTextDetails(text: text, tabId: tabId),
        ),
      );

  @override
  Future<Result<void, BrowserError>> setBadgeBackgroundColor(
    String cssColor, {
    int? tabId,
  }) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_action.chrome.action.setBadgeBackgroundColor(
          chrome_action.SetBadgeBackgroundColorDetails(
            color: cssColor,
            tabId: tabId,
          ),
        ),
      );
}

/// Persistent timers, over `chrome.alarms`.
final class _ChromeAlarmsBackend implements AlarmsBackend {
  const _ChromeAlarmsBackend();

  static const String _api = 'chrome.alarms';

  bool get _isAvailable => chrome_alarms.chrome.alarms.isAvailable;

  @override
  Future<Result<void, BrowserError>> create(
    String name, {
    double? delayInMinutes,
    double? periodInMinutes,
  }) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_alarms.chrome.alarms.create(
          name,
          chrome_alarms.AlarmCreateInfo(
            delayInMinutes: delayInMinutes,
            periodInMinutes: periodInMinutes,
          ),
        ),
      );

  @override
  Future<Result<bool, BrowserError>> clear(String name) => _guardAsync<bool>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_alarms.chrome.alarms.clear(name),
      );

  @override
  Stream<AlarmFired> get onAlarm => chrome_alarms.chrome.alarms.onAlarm.map(
        (alarm) => AlarmFired(
          name: alarm.name,
          scheduledTime: alarm.scheduledTime,
          periodInMinutes: alarm.periodInMinutes,
        ),
      );
}

/// Optional host permissions, over `chrome.permissions`.
final class _ChromePermissionsBackend implements PermissionsBackend {
  const _ChromePermissionsBackend();

  static const String _api = 'chrome.permissions';

  bool get _isAvailable => chrome_permissions.chrome.permissions.isAvailable;

  @override
  Future<Result<bool, BrowserError>> containsHosts(List<String> origins) =>
      _guardAsync<bool>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_permissions.chrome.permissions.contains(
          chrome_permissions.Permissions(origins: origins),
        ),
      );

  @override
  Future<Result<bool, BrowserError>> requestHosts(List<String> origins) =>
      _guardAsync<bool>(
        _api,
        isAvailable: _isAvailable,
        body: () => chrome_permissions.chrome.permissions.request(
          chrome_permissions.Permissions(origins: origins),
        ),
      );
}

/// Programmatic injection, over `chrome.scripting`.
final class _ChromeScriptingBackend implements ScriptingBackend {
  const _ChromeScriptingBackend();

  static const String _api = 'chrome.scripting';

  bool get _isAvailable => chrome_scripting.chrome.scripting.isAvailable;

  @override
  Future<Result<void, BrowserError>> executeScriptFiles({
    required int tabId,
    required List<String> files,
  }) =>
      _guardAsync<void>(
        _api,
        isAvailable: _isAvailable,
        body: () async {
          // The injection results are dropped on purpose: they arrive from
          // the browser untyped, and no consumer of this call needs them.
          await chrome_scripting.chrome.scripting.executeScript(
            chrome_scripting.ScriptInjection(
              target: chrome_scripting.InjectionTarget(tabId: tabId),
              files: files,
            ),
          );
        },
      );

  @override
  Future<Result<String?, BrowserError>> executeScriptFilesForString({
    required int tabId,
    required List<String> files,
  }) =>
      _guardAsync<String?>(
        _api,
        isAvailable: _isAvailable,
        body: () async {
          final results = await chrome_scripting.chrome.scripting.executeScript(
            chrome_scripting.ScriptInjection(
              target: chrome_scripting.InjectionTarget(tabId: tabId),
              files: files,
            ),
          );
          if (results.isEmpty) {
            return null;
          }
          // One entry per injected frame; without allFrames that is the
          // top frame alone. The package dartifies the value; anything
          // but a string is dropped -- the contract transports exactly
          // one string.
          final value = results.first.result;
          return value is String ? value : null;
        },
      );
}

// ---------------------------------------------------------------------------
// webRequest, bound by hand (ADR-004).
//
// The binding package cannot serve this namespace: its EventStream registers
// every listener as a bare addListener(callback), and the browser omits the
// headers unless the listener is registered with an extraInfoSpec. The
// declarations below are exactly as wide as the two events need -- nothing
// else of webRequest is bound, and nothing here leaves this file.
// ---------------------------------------------------------------------------

/// The callback form of `chrome.action.setIcon`, bound by hand: its
/// failure surfaces only through `runtime.lastError`, which the
/// package's promise form never reads (see _ChromeActionBackend.setIcon).
@JS('chrome.action.setIcon')
external void _jsActionSetIconWithCallback(JSAny? details, JSFunction callback);

/// `chrome.runtime.lastError`; meaningful only inside an API callback.
@JS('chrome.runtime.lastError')
external _JSLastError? get _jsRuntimeLastError;

extension type _JSLastError._(JSObject _) implements JSObject {
  external String? get message;
}

/// The global `chrome` object, or null outside an extension context.
@JS('chrome')
external _JSChromeGlobal? get _jsChromeGlobal;

extension type _JSChromeGlobal._(JSObject _) implements JSObject {
  /// The webRequest namespace, or null when the manifest does not request
  /// the `webRequest` permission.
  @JS('webRequest')
  external _JSWebRequestNamespace? get webRequestNullable;
}

extension type _JSWebRequestNamespace._(JSObject _) implements JSObject {
  external _JSWebRequestEvent get onSendHeaders;
  external _JSWebRequestEvent get onHeadersReceived;
  external _JSWebRequestEvent get onResponseStarted;
}

extension type _JSWebRequestEvent._(JSObject _) implements JSObject {
  /// The three-argument registration the package cannot express: without
  /// [extraInfoSpec] the browser delivers the details with no header list.
  external void addListener(
    JSFunction callback,
    _JSRequestFilter filter,
    JSArray<JSString> extraInfoSpec,
  );

  external void removeListener(JSFunction callback);
}

extension type _JSRequestFilter._(JSObject _) implements JSObject {
  external factory _JSRequestFilter({JSArray<JSString> urls});
}

extension type _JSWebRequestDetails._(JSObject _) implements JSObject {
  external String get requestId;
  external String get url;
  external String get method;

  /// The resource type, `main_frame` and friends.
  external String get type;
  external int get tabId;
  external double get timeStamp;

  /// Present on onHeadersReceived only; read nowhere else.
  external int get statusCode;

  /// Optional in Chrome's schema; read only on onResponseStarted.
  external String? get ip;

  /// Required by Chrome's schema on onResponseStarted, where alone it is
  /// read; the JS name is fromCache.
  @JS('fromCache')
  external bool get fromCacheRequired;

  external JSArray<_JSHttpHeader>? get requestHeaders;
  external JSArray<_JSHttpHeader>? get responseHeaders;
}

extension type _JSHttpHeader._(JSObject _) implements JSObject {
  external String get name;

  /// Absent for the rare binary-valued header.
  external String? get value;
}

/// Converts a browser header array into the library list.
List<HttpHeader> _toHeaderList(JSArray<_JSHttpHeader>? array) {
  if (array == null) {
    return const <HttpHeader>[];
  }
  return List<HttpHeader>.unmodifiable(
    array.toDart.map(
      (item) => HttpHeader(name: item.name, value: item.value ?? ''),
    ),
  );
}

/// Header capture, over hand-written `chrome.webRequest` bindings (ADR-004).
final class _ChromeWebRequestBackend implements WebRequestBackend {
  const _ChromeWebRequestBackend();

  @override
  Result<Stream<RequestHeadersSent>, BrowserError> onSendHeaders() =>
      _webRequestStream(
        (namespace) => namespace.onSendHeaders,
        'requestHeaders',
        (details) => RequestHeadersSent(
          requestId: details.requestId,
          tabId: details.tabId,
          url: details.url,
          method: details.method,
          resourceType: details.type,
          timeStamp: details.timeStamp,
          headers: _toHeaderList(details.requestHeaders),
        ),
      );

  @override
  Result<Stream<ResponseHeadersReceived>, BrowserError> onHeadersReceived() =>
      _webRequestStream(
        (namespace) => namespace.onHeadersReceived,
        'responseHeaders',
        (details) => ResponseHeadersReceived(
          requestId: details.requestId,
          tabId: details.tabId,
          url: details.url,
          method: details.method,
          resourceType: details.type,
          statusCode: details.statusCode,
          timeStamp: details.timeStamp,
          headers: _toHeaderList(details.responseHeaders),
        ),
      );

  @override
  Result<Stream<ResponseStarted>, BrowserError> onResponseStarted() =>
      _webRequestStream(
        (namespace) => namespace.onResponseStarted,
        'responseHeaders',
        (details) => ResponseStarted(
          requestId: details.requestId,
          tabId: details.tabId,
          url: details.url,
          method: details.method,
          resourceType: details.type,
          statusCode: details.statusCode,
          ip: details.ip,
          fromCache: details.fromCacheRequired,
          timeStamp: details.timeStamp,
          headers: _toHeaderList(details.responseHeaders),
        ),
      );
}

/// Builds one registered event stream over the hand-written bindings.
///
/// The availability check happens here, at call time, and its failure is
/// the returned [Err]: a bare stream getter could only throw, and nothing
/// above browserkit throws. The filter is fixed to http and https; the
/// [extraInfo] string is what makes the browser attach the header list.
Result<Stream<T>, BrowserError> _webRequestStream<T>(
  _JSWebRequestEvent Function(_JSWebRequestNamespace namespace) eventOf,
  String extraInfo,
  T Function(_JSWebRequestDetails details) convert,
) {
  final namespace = _jsChromeGlobal?.webRequestNullable;
  if (namespace == null) {
    return const Err(NotAvailable('chrome.webRequest'));
  }
  final event = eventOf(namespace);
  JSFunction? registered;
  // The controller is deliberately never closed: the stream is handed to
  // the caller, the unit of cleanup is the caller's subscription (onCancel
  // below releases the browser listener), and the controller holds no
  // resource beyond memory.
  // ignore: close_sinks
  late final StreamController<T> controller;
  controller = StreamController<T>.broadcast(
    onListen: () {
      final callback = ((_JSWebRequestDetails details) {
        controller.add(convert(details));
      }).toJS;
      registered = callback;
      event.addListener(
        callback,
        _JSRequestFilter(urls: ['http://*/*'.toJS, 'https://*/*'.toJS].toJS),
        [extraInfo.toJS].toJS,
      );
    },
    onCancel: () {
      final callback = registered;
      if (callback != null) {
        event.removeListener(callback);
        registered = null;
      }
    },
  );
  return Ok(controller.stream);
}
