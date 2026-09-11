// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The result type used by every call that can fail.
///
/// An extension has no user-visible crash. A thrown exception inside a
/// service worker disappears into a console nobody reads, so failure has to
/// be a value the calling code is forced to look at.
library;

/// The outcome of an operation: either a value or an error, never both.
///
/// Switch over it exhaustively; the compiler then guarantees that no failure
/// is forgotten:
///
/// ```dart
/// switch (await tabs.query(const TabQuery())) {
///   case Ok(:final value):
///     handle(value);
///   case Err(:final error):
///     report(error);
/// }
/// ```
///
/// There is deliberately no `unwrap` that throws on an error. A caller that
/// wants to give up on failure says so explicitly, at the call site.
///
/// A `Result` has no value equality: two results are equal only when they
/// are the same object. A result is a transport for an outcome, not a value
/// in its own right, and payload-based equality silently degraded to
/// identity for collection payloads, which let tests pass by `const`
/// canonicalisation instead of by checking anything. Compare the unwrapped
/// payload explicitly; see ADR-003.
sealed class Result<T, E> {
  /// Const constructor for the two variants, [Ok] and [Err].
  const Result();

  /// Whether this result carries a value.
  ///
  /// Prefer an exhaustive switch where both cases are handled. This getter is
  /// for the places where only one branch is interesting.
  bool get isOk => switch (this) {
        Ok<T, E>() => true,
        Err<T, E>() => false,
      };

  /// Whether this result carries an error.
  bool get isErr => !isOk;

  /// Applies [transform] to the value of an [Ok] and passes an [Err] through
  /// untouched.
  ///
  /// The error type is preserved, so a chain of `map` calls keeps exactly one
  /// failure channel.
  Result<R, E> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T, E>(:final value) => Ok<R, E>(transform(value)),
        Err<T, E>(:final error) => Err<R, E>(error),
      };

  /// Applies [transform] to the error of an [Err] and passes an [Ok] through
  /// untouched.
  ///
  /// Used where a lower layer reports in one error vocabulary and the caller
  /// speaks another.
  Result<T, F> mapErr<F>(F Function(E error) transform) => switch (this) {
        Ok<T, E>(:final value) => Ok<T, F>(value),
        Err<T, E>(:final error) => Err<T, F>(transform(error)),
      };

  /// Returns the value of an [Ok], or [fallback] if this is an [Err].
  ///
  /// The error is discarded. Use it only where the failure genuinely carries
  /// no information for the caller, such as a cold cache read.
  T unwrapOr(T fallback) => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>() => fallback,
      };
}

/// A [Result] that carries a value.
final class Ok<T, E> extends Result<T, E> {
  /// Wraps [value] as a successful result.
  const Ok(this.value);

  /// The value the operation produced.
  final T value;

  @override
  String toString() => 'Ok($value)';
}

/// A [Result] that carries an error.
final class Err<T, E> extends Result<T, E> {
  /// Wraps [error] as a failed result.
  const Err(this.error);

  /// The error that ended the operation.
  final E error;

  @override
  String toString() => 'Err($error)';
}
