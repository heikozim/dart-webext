// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The error taxonomy, and the one place where a thrown browser error becomes
/// a value.
library;

/// Everything that can go wrong below the browser seam.
///
/// Five variants, closed on purpose: a consumer switching over them is told
/// by the compiler when a new one appears.
sealed class BrowserError {
  /// Const constructor for the five variants.
  const BrowserError();

  /// A short description, safe to log.
  ///
  /// It never contains a value the caller passed in, so logging it cannot
  /// leak page content.
  String get message;
}

/// The API is absent in this browser or in this context.
///
/// On Chrome this is reached whenever the namespace object is missing:
/// the manifest does not request the permission, or the API is not exposed to
/// the calling context. It is also the variant a future Firefox backend
/// returns for calls Chrome has and Firefox does not.
final class NotAvailable extends BrowserError {
  /// Records that [api] is not present.
  const NotAvailable(this.api);

  /// The namespace that is missing, as the browser names it, for example
  /// `chrome.tabs`.
  final String api;

  @override
  String get message => '$api is not available in this context';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NotAvailable && other.api == api;

  @override
  int get hashCode => Object.hash('NotAvailable', api);

  @override
  String toString() => 'NotAvailable($api)';
}

/// A host or API permission is missing.
///
/// Distinct from [NotAvailable]: the API is there, the caller may not use it
/// on this target. Requesting an optional permission can turn this into a
/// success, which is why it is worth telling the two apart.
final class PermissionDenied extends BrowserError {
  /// Records a refusal described by [detail], as reported by the browser.
  const PermissionDenied(this.detail);

  /// What the browser said, verbatim.
  final String detail;

  @override
  String get message => 'permission denied: $detail';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionDenied && other.detail == detail;

  @override
  int get hashCode => Object.hash('PermissionDenied', detail);

  @override
  String toString() => 'PermissionDenied($detail)';
}

/// The caller passed something the browser rejected.
///
/// This is a bug in the extension, not a condition to recover from. It is a
/// separate variant so that it shows up in logs as the defect it is instead
/// of hiding among transient failures.
final class InvalidArgument extends BrowserError {
  /// Records a rejected argument described by [detail].
  const InvalidArgument(this.detail);

  /// What the browser said, verbatim.
  final String detail;

  @override
  String get message => 'invalid argument: $detail';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvalidArgument && other.detail == detail;

  @override
  int get hashCode => Object.hash('InvalidArgument', detail);

  @override
  String toString() => 'InvalidArgument($detail)';
}

/// The tab disappeared between the call and the response.
///
/// Entirely normal: the user closed it. Consumers treat it as an expected
/// outcome, not as an error to report.
final class TabGone extends BrowserError {
  /// Records the loss of the tab with [tabId].
  const TabGone(this.tabId);

  /// The tab that vanished, or null when the browser reported the loss
  /// without naming it.
  final int? tabId;

  @override
  String get message =>
      tabId == null ? 'the tab is gone' : 'tab $tabId is gone';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TabGone && other.tabId == tabId;

  @override
  int get hashCode => Object.hash('TabGone', tabId);

  @override
  String toString() => 'TabGone($tabId)';
}

/// Anything the taxonomy does not recognise.
///
/// It carries the original [cause] so that a case worth its own variant can
/// be identified from a log rather than guessed at.
final class Unexpected extends BrowserError {
  /// Records an unrecognised failure described by [message], optionally
  /// carrying the [cause] that produced it.
  const Unexpected(this.message, {this.cause});

  @override
  final String message;

  /// The object that was thrown, when one was.
  final Object? cause;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Unexpected && other.message == message && other.cause == cause;

  @override
  int get hashCode => Object.hash('Unexpected', message, cause);

  @override
  String toString() =>
      cause == null ? 'Unexpected($message)' : 'Unexpected($message, $cause)';
}

/// Matches the browser message for a tab that no longer exists, capturing the
/// identifier when the browser names one.
///
/// The separator is `[^0-9-]*` and not `\D*` on purpose. A minus sign is a
/// non-digit, so a greedy `\D*` would swallow the sign of a negative
/// identifier and report tab 1 for a message about tab -1.
final RegExp _missingTabPattern = RegExp(
  r'(?:no tab with id|tab with id .* not found|invalid tab id)[^0-9-]*(-?\d+)?',
);

/// Turns a thrown browser error into a [BrowserError].
///
/// This is the single place where a message string is interpreted, and it is
/// deliberately the only one. `package:chrome_extension` throws untyped
/// values: a namespace that is absent produces its own exception type, and a
/// failed call produces a bare `Exception` whose message is the formatted
/// text of `chrome.runtime.lastError`. Nothing else about a failure is typed,
/// so telling [PermissionDenied] from [TabGone] can only be done by reading
/// that text.
///
/// That is fragile, and it is confined here on purpose: when a message
/// changes, one function is wrong instead of every consumer. Anything not
/// recognised becomes [Unexpected] rather than being guessed at, and carries
/// [thrown] as its cause so the log shows what was actually seen.
///
/// The order of the checks matters. A message can mention both a tab and a
/// permission, and the more specific reading wins.
BrowserError browserErrorFromThrown(Object thrown) {
  final text = thrown.toString();
  final lower = text.toLowerCase();

  // The absent-namespace exception of package:chrome_extension is recognised
  // by its own text, and this branch is load-bearing rather than a
  // convenience: the exception class is declared in lib/src/chrome_js.dart
  // and is not exported, so no caller can catch it by type. backend_chrome
  // therefore checks isAvailable first and relies on this branch for the
  // exception arriving from anywhere else, such as a rejected promise.
  if (lower.contains('apinotavailableexception')) {
    return NotAvailable(
        _between(text, 'ApiNotAvailableException: ', ' is not') ??
            'the requested API');
  }

  final missingTab = _missingTabPattern.firstMatch(lower);
  if (missingTab != null) {
    final captured = missingTab.group(1);
    return TabGone(captured == null ? null : int.tryParse(captured));
  }

  if (lower.contains('tab was closed') ||
      lower.contains('tab has been closed')) {
    return const TabGone(null);
  }

  if (lower.contains('permission') ||
      lower.contains('cannot access') ||
      lower.contains('cannot be scripted')) {
    return PermissionDenied(_withoutPrefix(text));
  }

  if (lower.contains('invalid') || lower.contains('must be')) {
    return InvalidArgument(_withoutPrefix(text));
  }

  return Unexpected(_withoutPrefix(text), cause: thrown);
}

/// Strips the noise Dart and the package add in front of the browser message,
/// so that a log shows what the browser said and not how it travelled.
String _withoutPrefix(String text) {
  var result = text;
  for (final prefix in const ['Exception: ', 'RuntimeLastError: ']) {
    if (result.startsWith(prefix)) {
      result = result.substring(prefix.length);
    }
  }
  return result;
}

/// Returns the text between [start] and [end], or null if either is absent.
String? _between(String text, String start, String end) {
  final from = text.indexOf(start);
  if (from < 0) {
    return null;
  }
  final to = text.indexOf(end, from + start.length);
  if (to < 0) {
    return null;
  }
  return text.substring(from + start.length, to);
}
