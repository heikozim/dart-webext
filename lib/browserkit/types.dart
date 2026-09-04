// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The vocabulary this library owns.
///
/// Every type here replaces one from `package:chrome_extension`, which must
/// not cross the `browserkit` boundary. The originals are read-write views
/// onto a JavaScript object and expose raw `Map` and `Object` members; these
/// are immutable and fully typed.
library;

/// A browser tab, reduced to the parts this library exposes.
///
/// Deliberately smaller than the browser structure. Fields are added when a
/// consumer needs them.
final class TabInfo {
  /// Describes a tab.
  const TabInfo({
    required this.id,
    required this.windowId,
    required this.index,
    required this.url,
    required this.title,
    required this.isActive,
  });

  /// The tab identifier, or null when the tab has none.
  ///
  /// The browser leaves this empty for contexts that are not really tabs, and
  /// for a tab that no longer exists. It is nullable here because it is
  /// nullable there; hiding that would only move the failure to a later and
  /// less obvious place.
  final int? id;

  /// The window the tab belongs to.
  final int windowId;

  /// The position of the tab within its window, counted from zero.
  final int index;

  /// The address the tab shows, or null when the extension may not read it.
  ///
  /// Reading a tab address requires a host permission. Without it the browser
  /// returns a tab with this field empty rather than failing the call, so an
  /// empty value here is a permission statement, not an error.
  final String? url;

  /// The tab title, or null when it is not available.
  final String? title;

  /// Whether the tab is the active one in its window.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabInfo &&
          other.id == id &&
          other.windowId == windowId &&
          other.index == index &&
          other.url == url &&
          other.title == title &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, windowId, index, url, title, isActive);

  @override
  String toString() => 'TabInfo(id: $id, windowId: $windowId, url: $url)';
}

/// A filter for [TabInfo] lookups.
///
/// Every field is optional; a field left null does not constrain the result.
/// An empty query matches every tab.
final class TabQuery {
  /// Builds a filter. Omitted fields do not constrain the result.
  const TabQuery({this.isActive, this.isInCurrentWindow, this.windowId});

  /// Restrict to active or to non-active tabs.
  final bool? isActive;

  /// Restrict to the window the caller runs in.
  final bool? isInCurrentWindow;

  /// Restrict to one window by identifier.
  final int? windowId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabQuery &&
          other.isActive == isActive &&
          other.isInCurrentWindow == isInCurrentWindow &&
          other.windowId == windowId;

  @override
  int get hashCode => Object.hash(isActive, isInCurrentWindow, windowId);

  @override
  String toString() =>
      'TabQuery(isActive: $isActive, isInCurrentWindow: $isInCurrentWindow, '
      'windowId: $windowId)';
}

/// A tab has been closed.
final class TabRemoved {
  /// Reports that the tab with [tabId] is gone.
  const TabRemoved({
    required this.tabId,
    required this.windowId,
    required this.isWindowClosing,
  });

  /// The tab that was closed.
  final int tabId;

  /// The window the tab was in.
  final int windowId;

  /// Whether the whole window is closing.
  ///
  /// When true, every other tab of that window is about to be reported as
  /// well, and per-tab cleanup will happen many times in quick succession.
  final bool isWindowClosing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabRemoved &&
          other.tabId == tabId &&
          other.windowId == windowId &&
          other.isWindowClosing == isWindowClosing;

  @override
  int get hashCode => Object.hash(tabId, windowId, isWindowClosing);

  @override
  String toString() => 'TabRemoved(tabId: $tabId, windowId: $windowId, '
      'isWindowClosing: $isWindowClosing)';
}

/// A tab has been replaced by another one, keeping its place.
///
/// Happens on prerendering and on instant navigation. State keyed by the old
/// identifier has to move, or it becomes unreachable while the user still
/// sees what looks like the same tab.
final class TabReplaced {
  /// Reports that [removedTabId] was replaced by [addedTabId].
  const TabReplaced({required this.addedTabId, required this.removedTabId});

  /// The tab that took the place.
  final int addedTabId;

  /// The tab that was replaced.
  final int removedTabId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabReplaced &&
          other.addedTabId == addedTabId &&
          other.removedTabId == removedTabId;

  @override
  int get hashCode => Object.hash(addedTabId, removedTabId);

  @override
  String toString() =>
      'TabReplaced(addedTabId: $addedTabId, removedTabId: $removedTabId)';
}

/// One HTTP header, as the browser reported it.
///
/// Order and repetition matter for headers, so they travel as a list of
/// these, never as a map. A header whose value the browser cannot represent
/// as text (a rare binary value) arrives with [value] empty; binary values
/// are not transported.
final class HttpHeader {
  /// Describes one header.
  const HttpHeader({required this.name, required this.value});

  /// The header name, in the casing the browser reported.
  final String name;

  /// The header value, or empty when the browser reported none.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpHeader && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => 'HttpHeader($name: $value)';
}

/// A request is about to leave, with the headers it carries.
///
/// The sending half of a request/response pair; [requestId] is the key that
/// pairs it with the matching [ResponseHeadersReceived].
final class RequestHeadersSent {
  /// Describes one outgoing request.
  const RequestHeadersSent({
    required this.requestId,
    required this.tabId,
    required this.url,
    required this.method,
    required this.resourceType,
    required this.timeStamp,
    required this.headers,
  });

  /// Identifies the request, uniquely within a browser session.
  final String requestId;

  /// The tab the request belongs to, or -1 when it belongs to none.
  final int tabId;

  /// The address the request goes to.
  final String url;

  /// The HTTP method.
  final String method;

  /// What kind of resource is requested, as the browser names it, for
  /// example `main_frame`, `sub_frame` or `xmlhttprequest`.
  final String resourceType;

  /// When the headers were sent, in milliseconds since the epoch.
  final double timeStamp;

  /// The request headers, in order, repetitions preserved. Unmodifiable.
  final List<HttpHeader> headers;

  @override
  String toString() => 'RequestHeadersSent(requestId: $requestId, '
      'tabId: $tabId, method: $method, url: $url)';
}

/// Response headers arrived -- once per hop of the request.
///
/// A redirected navigation keeps one [requestId] across its whole chain,
/// and this event fires for every hop: each 302 with its `Location`, then
/// the final answer (measured, ADR-005). It is the only event of the set
/// that sees the chain. The server address and the cache flag are not
/// here -- Chrome does not populate them on this event -- they arrive with
/// [ResponseStarted].
final class ResponseHeadersReceived {
  /// Describes one arrived response header block.
  const ResponseHeadersReceived({
    required this.requestId,
    required this.tabId,
    required this.url,
    required this.method,
    required this.resourceType,
    required this.statusCode,
    required this.timeStamp,
    required this.headers,
  });

  /// Identifies the request, uniquely within a browser session and stable
  /// across the hops of a redirect chain.
  final String requestId;

  /// The tab the request belongs to, or -1 when it belongs to none.
  final int tabId;

  /// The address this hop answered from.
  final String url;

  /// The HTTP method of the request.
  final String method;

  /// What kind of resource was requested, as the browser names it.
  final String resourceType;

  /// The HTTP status code of this hop.
  final int statusCode;

  /// When the headers arrived, in milliseconds since the epoch.
  final double timeStamp;

  /// The response headers of this hop, in order, repetitions preserved.
  /// Unmodifiable.
  final List<HttpHeader> headers;

  @override
  String toString() => 'ResponseHeadersReceived(requestId: $requestId, '
      'tabId: $tabId, statusCode: $statusCode, url: $url)';
}

/// The first byte of the final response is available.
///
/// Fires once per request, at the final destination of a redirect chain
/// (measured, ADR-005) -- pair it with the first [RequestHeadersSent] of
/// the same [requestId], and the difference of the two [timeStamp] values
/// is the time to first byte, the same quantity `curl` reports as
/// `time_starttransfer`.
final class ResponseStarted {
  /// Describes the start of one response body.
  const ResponseStarted({
    required this.requestId,
    required this.tabId,
    required this.url,
    required this.method,
    required this.resourceType,
    required this.statusCode,
    required this.ip,
    required this.fromCache,
    required this.timeStamp,
    required this.headers,
  });

  /// Identifies the request, uniquely within a browser session.
  final String requestId;

  /// The tab the request belongs to, or -1 when it belongs to none.
  final int tabId;

  /// The final address the response came from.
  final String url;

  /// The HTTP method of the request.
  final String method;

  /// What kind of resource was requested, as the browser names it.
  final String resourceType;

  /// The HTTP status code of the final answer.
  final int statusCode;

  /// The server address the request was sent to, or null when the browser
  /// reports none.
  ///
  /// Optional in Chrome's schema; populated in every measurement so far,
  /// cache hits included (ADR-005, M3). A consumer still handles null.
  final String? ip;

  /// Whether the response was served from cache.
  final bool fromCache;

  /// When the first byte was available, in milliseconds since the epoch.
  final double timeStamp;

  /// The response headers of the final answer, in order, repetitions
  /// preserved. Unmodifiable.
  final List<HttpHeader> headers;

  @override
  String toString() => 'ResponseStarted(requestId: $requestId, '
      'tabId: $tabId, statusCode: $statusCode, fromCache: $fromCache, '
      'url: $url)';
}

/// An alarm went off.
final class AlarmFired {
  /// Reports the firing of the alarm called [name].
  const AlarmFired({
    required this.name,
    required this.scheduledTime,
    required this.periodInMinutes,
  });

  /// The name the alarm was created under.
  final String name;

  /// When the alarm was scheduled to fire, in milliseconds since the epoch.
  ///
  /// A double because the browser reports it as one; an alarm delayed by a
  /// busy browser fires later than this value says.
  final double scheduledTime;

  /// The period for a repeating alarm, in minutes, or null for a one-shot.
  final double? periodInMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmFired &&
          other.name == name &&
          other.scheduledTime == scheduledTime &&
          other.periodInMinutes == periodInMinutes;

  @override
  int get hashCode => Object.hash(name, scheduledTime, periodInMinutes);

  @override
  String toString() => 'AlarmFired(name: $name, scheduledTime: '
      '$scheduledTime, periodInMinutes: $periodInMinutes)';
}

/// A message another part of this extension sent, with the one channel that
/// answers it.
///
/// Unlike the other types in this file it is a handle rather than a value:
/// [respond] closes over the browser's reply channel, so two incoming
/// messages are never interchangeable and the type deliberately keeps
/// identity equality.
final class IncomingMessage {
  /// Describes an incoming message whose reply channel is [respond].
  const IncomingMessage({required this.payload, required this.respond});

  /// What the sender passed to `sendMessage`, narrowed to a JSON object.
  final Map<String, Object?> payload;

  /// Delivers the reply to the sender, whose `sendMessage` future completes
  /// with it.
  ///
  /// Call it exactly once. The browser keeps the reply channel open until it
  /// is called, so a message that is never answered leaves its sender
  /// waiting; the browser accepts at most one reply per message.
  final void Function(Map<String, Object?> reply) respond;
}

/// Why an extension lifecycle install event fired.
enum InstallReason {
  /// The extension was installed for the first time.
  install,

  /// The extension was updated to a new version.
  update,

  /// The browser itself was updated.
  browserUpdate,

  /// A shared module the extension uses was updated.
  sharedModuleUpdate,

  /// The browser reported a reason this library does not know.
  ///
  /// Present so that a new browser value cannot turn into a crash or a silent
  /// mismatch. A consumer switching over this enum handles it like any other
  /// case.
  unknown,
}

/// The extension was installed, updated, or started after a browser update.
final class ExtensionInstalled {
  /// Reports an install event with its [reason].
  const ExtensionInstalled(
      {required this.reason, required this.previousVersion});

  /// Why the event fired.
  final InstallReason reason;

  /// The version that was in place before, for [InstallReason.update], and
  /// null otherwise.
  final String? previousVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionInstalled &&
          other.reason == reason &&
          other.previousVersion == previousVersion;

  @override
  int get hashCode => Object.hash(reason, previousVersion);

  @override
  String toString() =>
      'ExtensionInstalled(reason: $reason, previousVersion: $previousVersion)';
}
