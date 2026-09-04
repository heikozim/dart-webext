// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `runtime` facade: messaging and extension lifecycle.
///
/// One of the two facades written first, as the pattern the remaining six
/// follow. What that pattern is, and why, is spelled out on [RuntimeApi].
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';
import '../types.dart';

/// Messaging and extension lifecycle.
///
/// This class and `TabsApi` are the reference for every further facade. The
/// shape is deliberate and worth stating once, here, rather than being
/// inferred later from six inconsistent examples:
///
/// **A facade holds a [Backend] and nothing else.** It has no state of its
/// own, so it can be constructed anywhere, as often as convenient, and it
/// costs nothing. The backend is passed in rather than looked up, which is
/// what makes the class testable without a browser.
///
/// **Every call that can fail returns a [Result].** Nothing here throws, and
/// that is a promise the whole library rests on: the caller cannot ignore a
/// failure by forgetting a `catch`. Synchronous browser calls return a plain
/// [Result], asynchronous ones a `Future<Result<...>>` -- never a `Future`
/// that completes with an error.
///
/// **Argument checks that do not need the browser happen here.** An empty
/// path is [InvalidArgument] before any browser call is made. Doing it in the
/// facade means the same rejection in production and in tests, instead of
/// depending on what a particular browser build happens to complain about.
///
/// **Events are broadcast [Stream]s of library types.** The caller owns the
/// subscription and cancels it. A facade never holds a subscription itself,
/// because a facade has no lifetime to hang one on.
///
/// **No type from `package:chrome_extension` appears in any signature.** That
/// is the rule the later Firefox port depends on, and it is checked by the
/// fact that this file imports no such package.
final class RuntimeApi {
  /// Binds the facade to the given [Backend].
  ///
  /// Use `ChromeBackend` in an extension and `FakeBackend` in a test. The
  /// facade cannot tell the difference, which is the point.
  const RuntimeApi(this._backend);

  final Backend _backend;

  /// The identifier the browser assigned to this extension.
  ///
  /// Fails with [NotAvailable] when there is no runtime namespace, which
  /// happens in a page that is not part of the extension.
  Result<String, BrowserError> extensionId() => _backend.runtime.extensionId();

  /// Turns a path inside the extension package into an absolute URL.
  ///
  /// [path] is relative to the package root, with or without a leading
  /// slash. An empty path is rejected with [InvalidArgument] without
  /// consulting the browser.
  ///
  /// ```dart
  /// switch (runtime.urlForPath('icons/16.png')) {
  ///   case Ok(:final value):
  ///     showIcon(value);
  ///   case Err(:final error):
  ///     report(error.message);
  /// }
  /// ```
  Result<String, BrowserError> urlForPath(String path) {
    if (path.isEmpty) {
      return const Err<String, BrowserError>(
        InvalidArgument('path must not be empty'),
      );
    }
    return _backend.runtime.urlForPath(path);
  }

  /// Opens the options page the manifest declares, in the way the browser
  /// chooses to present it (`options_ui` decides tab or embedded view).
  ///
  /// Fails with [NotAvailable] when there is no runtime namespace, and
  /// with [Unexpected] when the manifest declares no options page -- the
  /// browser reports that case as a call failure, not as a missing
  /// namespace.
  Future<Result<void, BrowserError>> openOptionsPage() =>
      _backend.runtime.openOptionsPage();

  /// Sends [message] to the other parts of this extension and waits for the
  /// single reply.
  ///
  /// Messages are JSON objects in both directions. The browser would permit
  /// any JSON value; narrowing it to an object keeps the type honest, because
  /// the alternative is an `Object` that every caller has to test and cast.
  ///
  /// A reply of `{}` and no reply at all are the same thing here. The browser
  /// does not distinguish them either, so pretending otherwise would invent a
  /// difference that cannot be relied on.
  ///
  /// Fails with [NotAvailable] when there is no runtime namespace, and with
  /// [Unexpected] when no receiver answered.
  Future<Result<Map<String, Object?>, BrowserError>> sendMessage(
    Map<String, Object?> message,
  ) =>
      _backend.runtime.sendMessage(message);

  /// Messages sent to this extension by its other parts.
  ///
  /// The receiving half of [sendMessage]: a popup calls [sendMessage], the
  /// background listens here and answers through [IncomingMessage.respond],
  /// and the popup's future completes with that reply. In a service worker
  /// this event wakes the worker, provided the subscription was made
  /// synchronously during worker start-up -- a listener registered late
  /// misses the message that would have woken it.
  ///
  /// While a subscription is active, every incoming message keeps its reply
  /// channel open until respond is called. A consumer that never answers a
  /// message leaves its sender waiting, so answer every message, even if
  /// only with an empty object.
  ///
  /// A broadcast stream; the caller owns and cancels the subscription.
  Stream<IncomingMessage> get onMessage => _backend.runtime.onMessage;

  /// Fires when the extension is installed, updated, or started after a
  /// browser update.
  ///
  /// A broadcast stream: several listeners are fine and a late one simply
  /// misses what already happened. In a service worker this event is one of
  /// the few reliable moments to set up state, since the worker itself is
  /// terminated and restarted constantly.
  ///
  /// The subscription belongs to the caller and has to be cancelled.
  Stream<ExtensionInstalled> get onInstalled => _backend.runtime.onInstalled;

  /// Fires when a profile with this extension installed is started.
  ///
  /// Distinct from [onInstalled]: no version changed, the browser just
  /// started. Fires once per profile start, and not on a service worker
  /// restart, which is why it cannot be used to rebuild in-memory state.
  Stream<void> get onStartup => _backend.runtime.onStartup;
}
