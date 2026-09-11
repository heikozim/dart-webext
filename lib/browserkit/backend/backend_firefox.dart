// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The Firefox [Backend]: hand-written bindings over the `browser.*`
/// surface, derived from Mozilla's JSON schema files (ADR-007) --
/// no binding package, no generator. Each namespace section below
/// names the schema file and revision it was written from; the guard
/// `tool/check_firefox_schemas.dart` watches those files by hash.
///
/// BUILD IN PROGRESS (plan of 2026-09-02, approved): webRequest is
/// bound and measured first, per the approved order; every other
/// namespace answers [NotAvailable] with an explicit "not yet bound"
/// detail and is NOT security theater -- it declares its own absence
/// (SEC-026). The entry point `browserkit_firefox.dart` exists and
/// carries the same build-in-progress notice; a consumer reaching an
/// unbound namespace gets the explicit NotAvailable, never silence.
///
/// Differences to the Chrome side that live HERE and nowhere else:
/// `browser.*` instead of `chrome.*`, and errors arriving as promise
/// rejections instead of `runtime.lastError` -- both invisible above
/// the seam.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../error.dart';
import '../result.dart';
import '../types.dart';
import 'backend.dart';

/// Firefox, behind the [Backend] interface.
final class FirefoxBackend implements Backend {
  /// Binds to the `browser` object of the surrounding extension context.
  FirefoxBackend();

  @override
  final RuntimeBackend runtime = const _FirefoxRuntimeBackend();

  @override
  final TabsBackend tabs = const _FirefoxTabsBackend();

  @override
  final StorageAreaBackend sessionStorage =
      const _FirefoxStorageAreaBackend(_FirefoxStorageArea.session);

  @override
  final StorageAreaBackend syncStorage =
      const _FirefoxStorageAreaBackend(_FirefoxStorageArea.sync);

  @override
  final ActionBackend action = const _FirefoxActionBackend();

  @override
  final AlarmsBackend alarms = const _FirefoxAlarmsBackend();

  @override
  final PermissionsBackend permissions = const _FirefoxPermissionsBackend();

  @override
  final ScriptingBackend scripting = const _FirefoxScriptingBackend();

  @override
  final WebRequestBackend webRequest = const _FirefoxWebRequestBackend();
}

// ---------------------------------------------------------------------------
// webRequest, bound by hand.
//
// Source schema: toolkit/components/extensions/schemas/web_request.json
// at mozilla-firefox/firefox revision
// e0a4d7dffe243b078510928b5d1290b663576d9f (fetched 2026-09-02, sha256
// 05bd941e5aa3c5acf2f1036476ee12c4259f47a5f4b9986af5e23951fbe538d6 --
// pinned in tool/check_firefox_schemas.dart).
//
// The schema declares, for onSendHeaders / onHeadersReceived /
// onResponseStarted, the extraParameters (filter: RequestFilter,
// extraInfoSpec: array) -- the pass-through Chrome's binding package
// could not offer and ADR-004 had to hand-build. The detail fields
// this backend reads exist in the schema on the events named:
// requestHeaders on onSendHeaders; responseHeaders and statusCode on
// onHeadersReceived and onResponseStarted; ip and fromCache on
// onResponseStarted alone.
// ---------------------------------------------------------------------------

/// The global `browser` object, or null outside a Firefox extension
/// context.
@JS('browser')
external _JSBrowserGlobal? get _jsBrowserGlobal;

extension type _JSBrowserGlobal._(JSObject _) implements JSObject {
  @JS('webRequest')
  external _JSWebRequestNamespace? get webRequestNullable;
  @JS('runtime')
  external _JSRuntimeNamespace? get runtimeNullable;
  @JS('storage')
  external _JSStorageNamespace? get storageNullable;
  @JS('action')
  external _JSActionNamespace? get actionNullable;
  @JS('tabs')
  external _JSTabsNamespace? get tabsNullable;
  @JS('alarms')
  external _JSAlarmsNamespace? get alarmsNullable;
  @JS('permissions')
  external _JSPermissionsNamespace? get permissionsNullable;
  @JS('scripting')
  external _JSScriptingNamespace? get scriptingNullable;
}

extension type _JSWebRequestNamespace._(JSObject _) implements JSObject {
  external _JSWebRequestEvent get onSendHeaders;
  external _JSWebRequestEvent get onHeadersReceived;
  external _JSWebRequestEvent get onResponseStarted;
}

extension type _JSWebRequestEvent._(JSObject _) implements JSObject {
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

  /// Present on onHeadersReceived and onResponseStarted; read there
  /// alone.
  external int get statusCode;

  /// Optional in the schema; read only on onResponseStarted.
  external String? get ip;

  /// Read only on onResponseStarted; nullable read even though the
  /// schema marks it optional=false there -- the runtime object is the
  /// authority, and a missing field must not throw.
  external bool? get fromCache;

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

/// Header capture over the hand-written `browser.webRequest` bindings.
final class _FirefoxWebRequestBackend implements WebRequestBackend {
  const _FirefoxWebRequestBackend();

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
          fromCache: details.fromCache ?? false,
          timeStamp: details.timeStamp,
          headers: _toHeaderList(details.responseHeaders),
        ),
      );
}

/// Builds one registered event stream over the hand-written bindings.
///
/// Same shape as the Chrome side (ADR-004): availability is checked at
/// call time and a failure is the returned [Err]; the filter is fixed
/// to http and https; the [extraInfo] string is what makes the browser
/// attach the header list.
Result<Stream<T>, BrowserError> _webRequestStream<T>(
  _JSWebRequestEvent Function(_JSWebRequestNamespace namespace) eventOf,
  String extraInfo,
  T Function(_JSWebRequestDetails details) convert,
) {
  final namespace = _jsBrowserGlobal?.webRequestNullable;
  if (namespace == null) {
    return const Err(NotAvailable('browser.webRequest'));
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

// ---------------------------------------------------------------------------
// runtime, storage and action, bound by hand (plan step 3).
//
// Source schemas at mozilla-firefox/firefox revision
// e0a4d7dffe243b078510928b5d1290b663576d9f (fetched 2026-09-02; hashes
// pinned in tool/check_firefox_schemas.dart):
//   toolkit/components/extensions/schemas/runtime.json
//   toolkit/components/extensions/schemas/storage.json
//   toolkit/components/extensions/schemas/browser_action.json
//     (defines the MV3 `action` namespace; its setter details $import
//     the Details type, whose tabId is optional)
//
// Firefox reports failures as promise rejections through the normal
// guard below -- no runtime.lastError side channel, so no hand-bound
// callback forms like the Chrome setIcon fix.
// ---------------------------------------------------------------------------

/// Runs [body] and converts anything it throws into a [BrowserError];
/// [what] names the absent namespace when [available] is false.
Future<Result<T, BrowserError>> _guardFf<T>(
  String what, {
  required bool available,
  required Future<T> Function() body,
}) async {
  if (!available) {
    return Err<T, BrowserError>(NotAvailable(what));
  }
  try {
    return Ok<T, BrowserError>(await body());
  } on Object catch (thrown) {
    return Err<T, BrowserError>(browserErrorFromThrown(thrown));
  }
}

/// Narrows an untyped value from the browser to a JSON object; the
/// same stop-the-raw-types rule as the Chrome backend documents.
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

/// One registered browser event as a broadcast stream, listener held
/// only while someone listens (the webRequest pattern without filter).
Stream<T> _eventStream<T>(
  _JSSimpleEvent? Function() eventOf,
  JSFunction Function(void Function(T value) emit) makeCallback,
) {
  JSFunction? registered;
  // ignore: close_sinks
  late final StreamController<T> controller;
  controller = StreamController<T>.broadcast(
    onListen: () {
      final event = eventOf();
      if (event == null) {
        return; // Absent namespace: an event stream that never fires.
      }
      final callback = makeCallback(controller.add);
      registered = callback;
      event.addListener(callback);
    },
    onCancel: () {
      final callback = registered;
      if (callback != null) {
        eventOf()?.removeListener(callback);
        registered = null;
      }
    },
  );
  return controller.stream;
}

extension type _JSSimpleEvent._(JSObject _) implements JSObject {
  external void addListener(JSFunction callback);
  external void removeListener(JSFunction callback);
}

// --- runtime -----------------------------------------------------------

extension type _JSRuntimeNamespace._(JSObject _) implements JSObject {
  external String get id;
  external String getURL(String path);
  external JSPromise<JSAny?> openOptionsPage();
  external JSPromise<JSAny?> sendMessage(JSAny? message);
  external _JSSimpleEvent get onMessage;
  external _JSSimpleEvent get onInstalled;
  external _JSSimpleEvent get onStartup;
}

extension type _JSInstalledDetails._(JSObject _) implements JSObject {
  external String get reason;
  external String? get previousVersion;
}

/// Messaging and lifecycle, over `browser.runtime`.
final class _FirefoxRuntimeBackend implements RuntimeBackend {
  const _FirefoxRuntimeBackend();

  _JSRuntimeNamespace? get _namespace => _jsBrowserGlobal?.runtimeNullable;

  @override
  Result<String, BrowserError> extensionId() {
    final namespace = _namespace;
    if (namespace == null) {
      return const Err(NotAvailable('browser.runtime'));
    }
    try {
      return Ok(namespace.id);
    } on Object catch (thrown) {
      return Err(browserErrorFromThrown(thrown));
    }
  }

  @override
  Result<String, BrowserError> urlForPath(String path) {
    if (path.isEmpty) {
      return const Err<String, BrowserError>(
        InvalidArgument('path must not be empty'),
      );
    }
    final namespace = _namespace;
    if (namespace == null) {
      return const Err(NotAvailable('browser.runtime'));
    }
    try {
      return Ok(namespace.getURL(path));
    } on Object catch (thrown) {
      return Err(browserErrorFromThrown(thrown));
    }
  }

  @override
  Future<Result<void, BrowserError>> openOptionsPage() => _guardFf<void>(
        'browser.runtime',
        available: _namespace != null,
        body: () async {
          await _namespace!.openOptionsPage().toDart;
        },
      );

  @override
  Future<Result<Map<String, Object?>, BrowserError>> sendMessage(
    Map<String, Object?> message,
  ) =>
      _guardFf<Map<String, Object?>>(
        'browser.runtime',
        available: _namespace != null,
        body: () async {
          final reply = await _namespace!.sendMessage(message.jsify()).toDart;
          return _asJsonObject(reply.dartify());
        },
      );

  @override
  Stream<IncomingMessage> get onMessage {
    JSFunction? registered;
    // ignore: close_sinks
    late final StreamController<IncomingMessage> controller;
    controller = StreamController<IncomingMessage>.broadcast(
      onListen: () {
        final event = _namespace?.onMessage;
        if (event == null) {
          return;
        }
        // The listener returns true so the browser keeps the reply
        // channel open until respond is called -- the same contract the
        // Chrome side documents; Firefox supports the sendResponse
        // style alongside its promise style.
        final callback =
            ((JSAny? message, JSAny? sender, JSFunction sendResponse) {
          controller.add(
            IncomingMessage(
              payload: _asJsonObject(message.dartify()),
              respond: (reply) {
                sendResponse.callAsFunction(null, reply.jsify());
              },
            ),
          );
          return true.toJS;
        }).toJS;
        registered = callback;
        event.addListener(callback);
      },
      onCancel: () {
        final callback = registered;
        if (callback != null) {
          _namespace?.onMessage.removeListener(callback);
          registered = null;
        }
      },
    );
    return controller.stream;
  }

  @override
  Stream<ExtensionInstalled> get onInstalled => _eventStream(
        () => _namespace?.onInstalled,
        (emit) => ((_JSInstalledDetails details) {
          emit(
            ExtensionInstalled(
              // The schema enum is install | update | browser_update;
              // anything unrecognised must not break a listener.
              reason: switch (details.reason) {
                'install' => InstallReason.install,
                'update' => InstallReason.update,
                'browser_update' => InstallReason.browserUpdate,
                _ => InstallReason.unknown,
              },
              previousVersion: details.previousVersion,
            ),
          );
        }).toJS,
      );

  @override
  Stream<void> get onStartup => _eventStream(
        () => _namespace?.onStartup,
        (emit) => (() {
          emit(null);
        }).toJS,
      );
}

// --- storage -----------------------------------------------------------

extension type _JSStorageNamespace._(JSObject _) implements JSObject {
  external _JSStorageAreaJs? get session;
  external _JSStorageAreaJs? get sync;
}

extension type _JSStorageAreaJs._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> get(JSAny? keys);
  external JSPromise<JSAny?> set(JSAny items);
  external JSPromise<JSAny?> remove(JSAny keys);
}

/// The two areas this backend serves.
enum _FirefoxStorageArea { session, sync }

/// One storage area over `browser.storage`.
///
/// `browser.storage.session` exists from Firefox 115 on; on an older
/// browser the getter is null and every call answers [NotAvailable] --
/// a value, never a throw.
final class _FirefoxStorageAreaBackend implements StorageAreaBackend {
  const _FirefoxStorageAreaBackend(this._area);

  final _FirefoxStorageArea _area;

  _JSStorageAreaJs? get _areaJs {
    final namespace = _jsBrowserGlobal?.storageNullable;
    return switch (_area) {
      _FirefoxStorageArea.session => namespace?.session,
      _FirefoxStorageArea.sync => namespace?.sync,
    };
  }

  String get _name => 'browser.storage.${_area.name}';

  @override
  Future<Result<Map<String, Object?>?, BrowserError>> read(String key) =>
      _guardFf<Map<String, Object?>?>(
        _name,
        available: _areaJs != null,
        body: () async {
          final bag = await _areaJs!.get(key.toJS).toDart;
          final asMap = _asJsonObject(bag.dartify());
          final value = asMap[key];
          return value == null ? null : _asJsonObject(value);
        },
      );

  @override
  Future<Result<void, BrowserError>> write(
    String key,
    Map<String, Object?> value,
  ) =>
      _guardFf<void>(
        _name,
        available: _areaJs != null,
        body: () async {
          await _areaJs!.set(<String, Object?>{key: value}.jsify()!).toDart;
        },
      );

  @override
  Future<Result<void, BrowserError>> remove(String key) => _guardFf<void>(
        _name,
        available: _areaJs != null,
        body: () async {
          await _areaJs!.remove(key.toJS).toDart;
        },
      );
}

// --- action ------------------------------------------------------------

extension type _JSActionNamespace._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> setIcon(JSObject details);
  external JSPromise<JSAny?> setTitle(JSObject details);
  external JSPromise<JSAny?> setBadgeText(JSObject details);
  external JSPromise<JSAny?> setBadgeBackgroundColor(JSObject details);
}

/// Toolbar control over `browser.action`.
final class _FirefoxActionBackend implements ActionBackend {
  const _FirefoxActionBackend();

  _JSActionNamespace? get _namespace => _jsBrowserGlobal?.actionNullable;

  /// A details object literal; tabId stays ABSENT (not null) when the
  /// call is global -- the schema marks it optional, and an explicit
  /// null is not the same statement.
  JSObject _details(int? tabId) {
    final details = JSObject();
    if (tabId != null) {
      details['tabId'] = tabId.toJS;
    }
    return details;
  }

  @override
  Future<Result<void, BrowserError>> setIcon(
    Map<String, String> pathBySize, {
    int? tabId,
  }) =>
      _guardFf<void>(
        'browser.action',
        available: _namespace != null,
        body: () async {
          final path = JSObject();
          for (final entry in pathBySize.entries) {
            path[entry.key] = entry.value.toJS;
          }
          final details = _details(tabId);
          details['path'] = path;
          await _namespace!.setIcon(details).toDart;
        },
      );

  @override
  Future<Result<void, BrowserError>> setTitle(
    String title, {
    int? tabId,
  }) =>
      _guardFf<void>(
        'browser.action',
        available: _namespace != null,
        body: () async {
          final details = _details(tabId);
          details['title'] = title.toJS;
          await _namespace!.setTitle(details).toDart;
        },
      );

  @override
  Future<Result<void, BrowserError>> setBadgeText(
    String text, {
    int? tabId,
  }) =>
      _guardFf<void>(
        'browser.action',
        available: _namespace != null,
        body: () async {
          final details = _details(tabId);
          details['text'] = text.toJS;
          await _namespace!.setBadgeText(details).toDart;
        },
      );

  @override
  Future<Result<void, BrowserError>> setBadgeBackgroundColor(
    String color, {
    int? tabId,
  }) =>
      _guardFf<void>(
        'browser.action',
        available: _namespace != null,
        body: () async {
          final details = _details(tabId);
          details['color'] = color.toJS;
          await _namespace!.setBadgeBackgroundColor(details).toDart;
        },
      );
}

// ---------------------------------------------------------------------------
// tabs, alarms, permissions and scripting, bound by hand (plan step 4).
//
// Source schemas at mozilla-firefox/firefox revision
// e0a4d7dffe243b078510928b5d1290b663576d9f (fetched 2026-09-02; hashes
// pinned in tool/check_firefox_schemas.dart):
//   browser/components/extensions/schemas/tabs.json
//   toolkit/components/extensions/schemas/alarms.json
//   toolkit/components/extensions/schemas/permissions.json
//   toolkit/components/extensions/schemas/scripting.json
// ---------------------------------------------------------------------------

// --- tabs --------------------------------------------------------------

extension type _JSTabsNamespace._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_JSTab>> query(JSObject queryInfo);
  external _JSSimpleEvent get onRemoved;
  external _JSSimpleEvent get onReplaced;
}

extension type _JSTab._(JSObject _) implements JSObject {
  external int? get id;
  external int? get windowId;
  external int get index;
  external String? get url;
  external String? get title;
  external bool get active;
}

extension type _JSTabRemoveInfo._(JSObject _) implements JSObject {
  external int get windowId;
  external bool get isWindowClosing;
}

/// Tab queries and lifecycle events over `browser.tabs`.
final class _FirefoxTabsBackend implements TabsBackend {
  const _FirefoxTabsBackend();

  _JSTabsNamespace? get _namespace => _jsBrowserGlobal?.tabsNullable;

  @override
  Future<Result<List<TabInfo>, BrowserError>> query(TabQuery query) =>
      _guardFf<List<TabInfo>>(
        'browser.tabs',
        available: _namespace != null,
        body: () async {
          final info = JSObject();
          final active = query.isActive;
          if (active != null) {
            info['active'] = active.toJS;
          }
          final currentWindow = query.isInCurrentWindow;
          if (currentWindow != null) {
            info['currentWindow'] = currentWindow.toJS;
          }
          final windowId = query.windowId;
          if (windowId != null) {
            info['windowId'] = windowId.toJS;
          }
          final found = await _namespace!.query(info).toDart;
          // Firefox's schema marks Tab.windowId optional (the surface
          // comparison flags the difference); the library type requires
          // it. A tab without a window is none a TabQuery consumer can
          // mean, so such a row is dropped rather than given an
          // invented id.
          return List<TabInfo>.unmodifiable(
            found.toDart.where((tab) => tab.windowId != null).map(
                  (tab) => TabInfo(
                    id: tab.id,
                    windowId: tab.windowId!,
                    index: tab.index,
                    url: tab.url,
                    title: tab.title,
                    isActive: tab.active,
                  ),
                ),
          );
        },
      );

  @override
  Stream<TabRemoved> get onRemoved => _eventStream(
        () => _namespace?.onRemoved,
        (emit) => ((JSNumber tabId, _JSTabRemoveInfo removeInfo) {
          emit(
            TabRemoved(
              tabId: tabId.toDartInt,
              windowId: removeInfo.windowId,
              isWindowClosing: removeInfo.isWindowClosing,
            ),
          );
        }).toJS,
      );

  @override
  Stream<TabReplaced> get onReplaced => _eventStream(
        () => _namespace?.onReplaced,
        (emit) => ((JSNumber addedTabId, JSNumber removedTabId) {
          emit(
            TabReplaced(
              addedTabId: addedTabId.toDartInt,
              removedTabId: removedTabId.toDartInt,
            ),
          );
        }).toJS,
      );
}

// --- alarms ------------------------------------------------------------

extension type _JSAlarmsNamespace._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> create(String name, JSObject alarmInfo);
  external JSPromise<JSBoolean> clear(String name);
  external _JSSimpleEvent get onAlarm;
}

extension type _JSAlarm._(JSObject _) implements JSObject {
  external String get name;
  external double get scheduledTime;
  external double? get periodInMinutes;
}

/// Periodic work over `browser.alarms`.
final class _FirefoxAlarmsBackend implements AlarmsBackend {
  const _FirefoxAlarmsBackend();

  _JSAlarmsNamespace? get _namespace => _jsBrowserGlobal?.alarmsNullable;

  @override
  Future<Result<void, BrowserError>> create(
    String name, {
    double? delayInMinutes,
    double? periodInMinutes,
  }) =>
      _guardFf<void>(
        'browser.alarms',
        available: _namespace != null,
        body: () async {
          final info = JSObject();
          if (delayInMinutes != null) {
            info['delayInMinutes'] = delayInMinutes.toJS;
          }
          if (periodInMinutes != null) {
            info['periodInMinutes'] = periodInMinutes.toJS;
          }
          await _namespace!.create(name, info).toDart;
        },
      );

  @override
  Future<Result<bool, BrowserError>> clear(String name) => _guardFf<bool>(
        'browser.alarms',
        available: _namespace != null,
        body: () async => (await _namespace!.clear(name).toDart).toDart,
      );

  @override
  Stream<AlarmFired> get onAlarm => _eventStream(
        () => _namespace?.onAlarm,
        (emit) => ((_JSAlarm alarm) {
          emit(
            AlarmFired(
              name: alarm.name,
              scheduledTime: alarm.scheduledTime,
              periodInMinutes: alarm.periodInMinutes,
            ),
          );
        }).toJS,
      );
}

// --- permissions -------------------------------------------------------

extension type _JSPermissionsNamespace._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> contains(JSObject permissions);
  external JSPromise<JSBoolean> request(JSObject permissions);
}

/// Host permission checks over `browser.permissions`.
final class _FirefoxPermissionsBackend implements PermissionsBackend {
  const _FirefoxPermissionsBackend();

  _JSPermissionsNamespace? get _namespace =>
      _jsBrowserGlobal?.permissionsNullable;

  JSObject _origins(List<String> origins) {
    final permissions = JSObject();
    permissions['origins'] = origins.map((origin) => origin.toJS).toList().toJS;
    return permissions;
  }

  @override
  Future<Result<bool, BrowserError>> containsHosts(List<String> origins) =>
      _guardFf<bool>(
        'browser.permissions',
        available: _namespace != null,
        body: () async =>
            (await _namespace!.contains(_origins(origins)).toDart).toDart,
      );

  @override
  Future<Result<bool, BrowserError>> requestHosts(List<String> origins) =>
      _guardFf<bool>(
        'browser.permissions',
        available: _namespace != null,
        body: () async =>
            (await _namespace!.request(_origins(origins)).toDart).toDart,
      );
}

// --- scripting ---------------------------------------------------------

extension type _JSScriptingNamespace._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_JSInjectionResult>> executeScript(
    JSObject injection,
  );
}

extension type _JSInjectionResult._(JSObject _) implements JSObject {
  external JSAny? get result;
}

/// Programmatic injection over `browser.scripting`.
final class _FirefoxScriptingBackend implements ScriptingBackend {
  const _FirefoxScriptingBackend();

  _JSScriptingNamespace? get _namespace => _jsBrowserGlobal?.scriptingNullable;

  JSObject _injection(int tabId, List<String> files) {
    final target = JSObject();
    target['tabId'] = tabId.toJS;
    final injection = JSObject();
    injection['target'] = target;
    injection['files'] = files.map((file) => file.toJS).toList().toJS;
    return injection;
  }

  @override
  Future<Result<void, BrowserError>> executeScriptFiles({
    required int tabId,
    required List<String> files,
  }) =>
      _guardFf<void>(
        'browser.scripting',
        available: _namespace != null,
        body: () async {
          // The injection results are dropped on purpose, mirroring the
          // Chrome side: no consumer of this call needs them.
          await _namespace!.executeScript(_injection(tabId, files)).toDart;
        },
      );

  @override
  Future<Result<String?, BrowserError>> executeScriptFilesForString({
    required int tabId,
    required List<String> files,
  }) =>
      _guardFf<String?>(
        'browser.scripting',
        available: _namespace != null,
        body: () async {
          final results =
              await _namespace!.executeScript(_injection(tabId, files)).toDart;
          final list = results.toDart;
          if (list.isEmpty) {
            return null;
          }
          // One entry per injected frame; the contract transports the
          // top frame's completion value as exactly one string.
          final value = list.first.result.dartify();
          return value is String ? value : null;
        },
      );
}
