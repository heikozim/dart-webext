// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The `alarms` facade: periodic work that survives worker restarts.
library;

import '../backend/backend.dart';
import '../error.dart';
import '../result.dart';
import '../types.dart';

/// Timers that survive a service worker restart.
///
/// Follows the facade pattern documented on `RuntimeApi`.
///
/// This is the one sanctioned way to do periodic work in a service worker.
/// A `Timer` dies with the worker and is never seen again; an alarm is
/// persisted by the browser, wakes the worker when it fires, and keeps
/// firing however often the worker was terminated in between -- provided
/// the [onAlarm] subscription is made synchronously during worker start-up.
final class AlarmsApi {
  /// Binds the facade to the given [Backend].
  const AlarmsApi(this._backend);

  final Backend _backend;

  /// Creates or replaces the alarm called [name].
  ///
  /// [delayInMinutes] schedules the first firing, [periodInMinutes] every
  /// further one; at least one of the two is required, and both must be
  /// positive when given, or the call is rejected with [InvalidArgument]
  /// without consulting the browser. An empty [name] is rejected the same
  /// way: two alarms cannot share it, and a nameless alarm cannot be
  /// cleared by name.
  ///
  /// The browser clamps short intervals for packed extensions; sub-minute
  /// periods are a development convenience, not a guarantee.
  Future<Result<void, BrowserError>> create(
    String name, {
    double? delayInMinutes,
    double? periodInMinutes,
  }) {
    if (name.isEmpty) {
      return _invalid('the alarm name must not be empty');
    }
    if (delayInMinutes == null && periodInMinutes == null) {
      return _invalid('an alarm needs a delay, a period, or both');
    }
    if (delayInMinutes != null && delayInMinutes <= 0) {
      return _invalid('the delay must be positive, got $delayInMinutes');
    }
    if (periodInMinutes != null && periodInMinutes <= 0) {
      return _invalid('the period must be positive, got $periodInMinutes');
    }
    return _backend.alarms.create(
      name,
      delayInMinutes: delayInMinutes,
      periodInMinutes: periodInMinutes,
    );
  }

  /// Clears the alarm called [name].
  ///
  /// The value reports whether an alarm of that name existed; clearing a
  /// name that does not is an [Ok] holding false, not an [Err]. An empty
  /// [name] is rejected with [InvalidArgument] without consulting the
  /// browser.
  Future<Result<bool, BrowserError>> clear(String name) {
    if (name.isEmpty) {
      return Future<Result<bool, BrowserError>>.value(
        const Err<bool, BrowserError>(
          InvalidArgument('the alarm name must not be empty'),
        ),
      );
    }
    return _backend.alarms.clear(name);
  }

  /// Fires when an alarm goes off.
  ///
  /// In a service worker, subscribe synchronously in `main`: the browser
  /// wakes the worker for the event, but only a listener registered during
  /// start-up receives the firing that caused the wake-up.
  ///
  /// A broadcast stream; the caller owns and cancels the subscription.
  Stream<AlarmFired> get onAlarm => _backend.alarms.onAlarm;

  Future<Result<void, BrowserError>> _invalid(String detail) =>
      Future<Result<void, BrowserError>>.value(
        Err<void, BrowserError>(InvalidArgument(detail)),
      );
}
