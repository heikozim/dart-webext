// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// A [Backend] made of plain Dart, for tests.
///
/// No interop, no browser, no timers. It runs under `dart test` on the Dart
/// VM in milliseconds, which is what makes every layer above `browserkit`
/// testable at all.
library;

import 'dart:async';

import '../error.dart';
import '../result.dart';
import '../types.dart';
import 'backend.dart';

/// A browser that exists only in memory.
///
/// Two controls, and they are the whole point of the class:
///
/// * the state each namespace answers from, which tests set up directly, and
/// * [FakeNamespace.armedError], which makes every following call of that
///   namespace return a chosen [BrowserError] until it is cleared.
///
/// The second is what allows a test for each error variant, including the
/// ones no implemented Chrome call currently produces.
///
/// Close it with [dispose] when the test ends; the event streams are sinks
/// and an unclosed one keeps the test isolate alive.
final class FakeBackend implements Backend {
  /// Creates an empty browser: no tabs, no stored values, no failures armed.
  FakeBackend();

  @override
  final FakeRuntimeBackend runtime = FakeRuntimeBackend();

  @override
  final FakeTabsBackend tabs = FakeTabsBackend();

  @override
  final FakeStorageAreaBackend sessionStorage = FakeStorageAreaBackend();

  @override
  final FakeStorageAreaBackend syncStorage = FakeStorageAreaBackend();

  @override
  final FakeActionBackend action = FakeActionBackend();

  @override
  final FakeAlarmsBackend alarms = FakeAlarmsBackend();

  @override
  final FakePermissionsBackend permissions = FakePermissionsBackend();

  @override
  final FakeScriptingBackend scripting = FakeScriptingBackend();

  @override
  final FakeWebRequestBackend webRequest = FakeWebRequestBackend();

  /// Closes the event streams of every namespace.
  ///
  /// Safe to call more than once.
  Future<void> dispose() async {
    await runtime.dispose();
    await tabs.dispose();
    await alarms.dispose();
    await webRequest.dispose();
  }
}

/// The failure switch shared by the fake namespaces.
///
/// A single armed error rather than a queue of scripted replies: a test that
/// has to count calls in order to know what it will get back is testing the
/// fake and not the code under test.
abstract base class FakeNamespace {
  /// The error every call of this namespace returns while it is set.
  ///
  /// Assign a [BrowserError] to make the namespace fail, assign null to make
  /// it succeed again. It is a plain field rather than a pair of methods
  /// because that is all it is.
  BrowserError? armedError;
}

/// The runtime namespace of a [FakeBackend].
final class FakeRuntimeBackend extends FakeNamespace implements RuntimeBackend {
  /// Creates a runtime with a fixed extension identifier.
  FakeRuntimeBackend({this.identifier = 'fake-extension-id'});

  /// The value [extensionId] returns.
  final String identifier;

  /// The reply [sendMessage] produces while no error is armed.
  Map<String, Object?> reply = const <String, Object?>{};

  /// Every message passed to [sendMessage], oldest first.
  ///
  /// A test asserts on what was sent, not only on what came back.
  final List<Map<String, Object?>> sentMessages = <Map<String, Object?>>[];

  /// How often [openOptionsPage] succeeded.
  int openOptionsPageCalls = 0;

  final StreamController<IncomingMessage> _incoming =
      StreamController<IncomingMessage>.broadcast();
  final StreamController<ExtensionInstalled> _installed =
      StreamController<ExtensionInstalled>.broadcast();
  final StreamController<void> _startup = StreamController<void>.broadcast();

  @override
  Result<String, BrowserError> extensionId() {
    final error = armedError;
    return error == null ? Ok<String, BrowserError>(identifier) : Err(error);
  }

  @override
  Result<String, BrowserError> urlForPath(String path) {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    if (path.isEmpty) {
      return const Err(InvalidArgument('path must not be empty'));
    }
    final suffix = path.startsWith('/') ? path.substring(1) : path;
    return Ok<String, BrowserError>('chrome-extension://$identifier/$suffix');
  }

  @override
  Future<Result<Map<String, Object?>, BrowserError>> sendMessage(
    Map<String, Object?> message,
  ) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    sentMessages.add(Map<String, Object?>.unmodifiable(message));
    return Ok<Map<String, Object?>, BrowserError>(reply);
  }

  @override
  Future<Result<void, BrowserError>> openOptionsPage() async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    openOptionsPageCalls += 1;
    return const Ok<void, BrowserError>(null);
  }

  @override
  Stream<IncomingMessage> get onMessage => _incoming.stream;

  @override
  Stream<ExtensionInstalled> get onInstalled => _installed.stream;

  @override
  Stream<void> get onStartup => _startup.stream;

  /// Delivers an incoming message to every listener.
  ///
  /// The test builds the [IncomingMessage] itself, so it owns the respond
  /// callback and can assert on what a consumer replied.
  void emitIncoming(IncomingMessage message) => _incoming.add(message);

  /// Delivers an install event to every listener.
  void emitInstalled(ExtensionInstalled event) => _installed.add(event);

  /// Delivers a startup event to every listener.
  void emitStartup() => _startup.add(null);

  /// Closes the event streams. Safe to call more than once.
  Future<void> dispose() async {
    await _incoming.close();
    await _installed.close();
    await _startup.close();
  }
}

/// The tabs namespace of a [FakeBackend].
final class FakeTabsBackend extends FakeNamespace implements TabsBackend {
  /// Creates a tabs namespace with no open tabs.
  FakeTabsBackend();

  /// The tabs [query] filters. Tests assign this directly.
  List<TabInfo> tabs = const <TabInfo>[];

  final StreamController<TabRemoved> _removed =
      StreamController<TabRemoved>.broadcast();
  final StreamController<TabReplaced> _replaced =
      StreamController<TabReplaced>.broadcast();

  @override
  Future<Result<List<TabInfo>, BrowserError>> query(TabQuery query) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    final matched = tabs
        .where(
          (tab) =>
              (query.isActive == null || tab.isActive == query.isActive) &&
              (query.windowId == null || tab.windowId == query.windowId),
        )
        .toList(growable: false);
    return Ok<List<TabInfo>, BrowserError>(
      List<TabInfo>.unmodifiable(matched),
    );
  }

  @override
  Stream<TabRemoved> get onRemoved => _removed.stream;

  @override
  Stream<TabReplaced> get onReplaced => _replaced.stream;

  /// Delivers a close event to every listener.
  ///
  /// Does not touch [tabs]; a test that wants both effects sets the list too.
  /// Keeping them separate is what allows a test for the case where the event
  /// arrives and the list is already stale.
  void emitRemoved(TabRemoved event) => _removed.add(event);

  /// Delivers a replacement event to every listener.
  void emitReplaced(TabReplaced event) => _replaced.add(event);

  /// Closes both event streams. Safe to call more than once.
  Future<void> dispose() async {
    await _removed.close();
    await _replaced.close();
  }
}

/// One key-value storage area of a [FakeBackend].
///
/// The fake browser has two of these, `sessionStorage` and `syncStorage`,
/// which behave identically; the lifetime difference of the real areas is
/// not modelled, only their contents.
final class FakeStorageAreaBackend extends FakeNamespace
    implements StorageAreaBackend {
  /// Creates an empty storage area.
  FakeStorageAreaBackend();

  /// What the area holds, by key. Tests read it to check what was written.
  final Map<String, Map<String, Object?>> stored =
      <String, Map<String, Object?>>{};

  /// How often [read] reached this object.
  ///
  /// The cache in front of the store is only worth having if it prevents
  /// reads, and a counter is the only way to assert that it did.
  int readCount = 0;

  /// How often [write] reached this object.
  int writeCount = 0;

  @override
  Future<Result<Map<String, Object?>?, BrowserError>> read(String key) async {
    readCount++;
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    return Ok<Map<String, Object?>?, BrowserError>(stored[key]);
  }

  @override
  Future<Result<void, BrowserError>> write(
    String key,
    Map<String, Object?> value,
  ) async {
    writeCount++;
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    stored[key] = Map<String, Object?>.unmodifiable(value);
    return const Ok<void, BrowserError>(null);
  }

  @override
  Future<Result<void, BrowserError>> remove(String key) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    stored.remove(key);
    return const Ok<void, BrowserError>(null);
  }
}

/// The toolbar button of a [FakeBackend].
///
/// Records every call so a test can assert on what was set, in order.
final class FakeActionBackend extends FakeNamespace implements ActionBackend {
  /// Creates an action namespace with nothing set.
  FakeActionBackend();

  /// Every icon change, oldest first.
  final List<({Map<String, String> pathBySize, int? tabId})> iconCalls =
      <({Map<String, String> pathBySize, int? tabId})>[];

  /// Every title change, oldest first.
  final List<({String title, int? tabId})> titleCalls =
      <({String title, int? tabId})>[];

  /// Every badge text change, oldest first.
  final List<({String text, int? tabId})> badgeTextCalls =
      <({String text, int? tabId})>[];

  /// Every badge background change, oldest first.
  final List<({String cssColor, int? tabId})> badgeColorCalls =
      <({String cssColor, int? tabId})>[];

  @override
  Future<Result<void, BrowserError>> setIcon(
    Map<String, String> pathBySize, {
    int? tabId,
  }) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    iconCalls.add((
      pathBySize: Map<String, String>.unmodifiable(pathBySize),
      tabId: tabId,
    ));
    return const Ok<void, BrowserError>(null);
  }

  @override
  Future<Result<void, BrowserError>> setTitle(String title,
      {int? tabId}) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    titleCalls.add((title: title, tabId: tabId));
    return const Ok<void, BrowserError>(null);
  }

  @override
  Future<Result<void, BrowserError>> setBadgeText(
    String text, {
    int? tabId,
  }) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    badgeTextCalls.add((text: text, tabId: tabId));
    return const Ok<void, BrowserError>(null);
  }

  @override
  Future<Result<void, BrowserError>> setBadgeBackgroundColor(
    String cssColor, {
    int? tabId,
  }) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    badgeColorCalls.add((cssColor: cssColor, tabId: tabId));
    return const Ok<void, BrowserError>(null);
  }
}

/// The alarms namespace of a [FakeBackend].
final class FakeAlarmsBackend extends FakeNamespace implements AlarmsBackend {
  /// Creates an alarms namespace with no alarms.
  FakeAlarmsBackend();

  /// Every create call, oldest first.
  final List<({String name, double? delayInMinutes, double? periodInMinutes})>
      created =
      <({String name, double? delayInMinutes, double? periodInMinutes})>[];

  /// The names currently known, mirroring what the browser would persist.
  ///
  /// [create] adds to it, [clear] removes from it and reports whether the
  /// name was there, exactly like the browser does.
  final Set<String> alarmNames = <String>{};

  final StreamController<AlarmFired> _fired =
      StreamController<AlarmFired>.broadcast();

  @override
  Future<Result<void, BrowserError>> create(
    String name, {
    double? delayInMinutes,
    double? periodInMinutes,
  }) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    created.add((
      name: name,
      delayInMinutes: delayInMinutes,
      periodInMinutes: periodInMinutes,
    ));
    alarmNames.add(name);
    return const Ok<void, BrowserError>(null);
  }

  @override
  Future<Result<bool, BrowserError>> clear(String name) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    return Ok<bool, BrowserError>(alarmNames.remove(name));
  }

  @override
  Stream<AlarmFired> get onAlarm => _fired.stream;

  /// Delivers an alarm firing to every listener.
  void emitAlarm(AlarmFired event) => _fired.add(event);

  /// Closes the event stream. Safe to call more than once.
  Future<void> dispose() async {
    await _fired.close();
  }
}

/// The permissions namespace of a [FakeBackend].
final class FakePermissionsBackend extends FakeNamespace
    implements PermissionsBackend {
  /// Creates a permissions namespace where nothing is granted.
  FakePermissionsBackend();

  /// The origins the fake browser considers granted.
  final Set<String> grantedOrigins = <String>{};

  /// Whether the fake user grants the next requests.
  ///
  /// False by default, because a test that forgets to decide should see the
  /// refusal path, not a silent success.
  bool userGrantsRequests = false;

  /// Every request call, oldest first.
  final List<List<String>> requested = <List<String>>[];

  @override
  Future<Result<bool, BrowserError>> containsHosts(
    List<String> origins,
  ) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    return Ok<bool, BrowserError>(origins.every(grantedOrigins.contains));
  }

  @override
  Future<Result<bool, BrowserError>> requestHosts(List<String> origins) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    requested.add(List<String>.unmodifiable(origins));
    if (userGrantsRequests) {
      grantedOrigins.addAll(origins);
    }
    return Ok<bool, BrowserError>(userGrantsRequests);
  }
}

/// The scripting namespace of a [FakeBackend].
final class FakeScriptingBackend extends FakeNamespace
    implements ScriptingBackend {
  /// Creates a scripting namespace that has injected nothing.
  FakeScriptingBackend();

  /// Every injection, oldest first -- both call forms record here.
  final List<({int tabId, List<String> files})> executions =
      <({int tabId, List<String> files})>[];

  /// What [executeScriptFilesForString] answers next. Null mirrors the
  /// browser reporting no result or a non-string one.
  String? stringResult;

  @override
  Future<Result<void, BrowserError>> executeScriptFiles({
    required int tabId,
    required List<String> files,
  }) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    executions.add((tabId: tabId, files: List<String>.unmodifiable(files)));
    return const Ok<void, BrowserError>(null);
  }

  @override
  Future<Result<String?, BrowserError>> executeScriptFilesForString({
    required int tabId,
    required List<String> files,
  }) async {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    executions.add((tabId: tabId, files: List<String>.unmodifiable(files)));
    return Ok<String?, BrowserError>(stringResult);
  }
}

/// The webRequest namespace of a [FakeBackend].
///
/// The registration methods mirror the production shape: they return a
/// [Result] and fail with the armed error, while the streams themselves are
/// fed by the test through [emitSent] and [emitReceived].
final class FakeWebRequestBackend extends FakeNamespace
    implements WebRequestBackend {
  /// Creates a webRequest namespace that has seen no traffic.
  FakeWebRequestBackend();

  final StreamController<RequestHeadersSent> _sent =
      StreamController<RequestHeadersSent>.broadcast();
  final StreamController<ResponseHeadersReceived> _received =
      StreamController<ResponseHeadersReceived>.broadcast();
  final StreamController<ResponseStarted> _started =
      StreamController<ResponseStarted>.broadcast();

  @override
  Result<Stream<RequestHeadersSent>, BrowserError> onSendHeaders() {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    return Ok(_sent.stream);
  }

  @override
  Result<Stream<ResponseHeadersReceived>, BrowserError> onHeadersReceived() {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    return Ok(_received.stream);
  }

  @override
  Result<Stream<ResponseStarted>, BrowserError> onResponseStarted() {
    final error = armedError;
    if (error != null) {
      return Err(error);
    }
    return Ok(_started.stream);
  }

  /// Delivers an outgoing-request event to every listener.
  void emitSent(RequestHeadersSent event) => _sent.add(event);

  /// Delivers a response-headers event to every listener.
  void emitReceived(ResponseHeadersReceived event) => _received.add(event);

  /// Delivers a response-started event to every listener.
  void emitStarted(ResponseStarted event) => _started.add(event);

  /// Closes the event streams. Safe to call more than once.
  Future<void> dispose() async {
    await _sent.close();
    await _received.close();
    await _started.close();
  }
}
