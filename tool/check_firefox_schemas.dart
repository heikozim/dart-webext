// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Guards the Firefox schema files the hand-written bindings of
/// `backend_firefox.dart` were derived from (ADR-007 decision 2).
///
/// Run from the package root:
///
///     dart run tool/check_firefox_schemas.dart
///
/// The bindings carry source file and revision in their headers; this
/// guard holds one SHA-256 per schema file AT that pinned revision and
/// re-fetches each file to compare. No schema copies live in this
/// repository (decision of 2026-09-02): the files are foreign material,
/// and the hash suffices for the comparison.
///
/// The guard additionally fetches the current head of the upstream
/// default branch and reports whether the pin is still the head --
/// informative only, never a failure: a moved head with unchanged
/// hashes means the schemas did not drift.
///
/// Why the built-in negative control exists: the historical source,
/// hg.mozilla.org/mozilla-central, died silently -- it answers 404 for
/// EVERY path, existing or not (measured 2026-09-02 while planning
/// these bindings). Against such a source, "file missing" and "source
/// dead" are indistinguishable, and a catch-all frontend answering 200
/// everywhere would fake integrity the same way. So every run also
/// fetches a nonsense path and demands a 404 for it; any other answer
/// invalidates the run.
library;

import 'dart:convert';
import 'dart:io';

/// The pinned upstream revision the binding headers name.
const String pinnedRevision = 'e0a4d7dffe243b078510928b5d1290b663576d9f';

/// The upstream repository (mozilla-central's primary home since the
/// move to GitHub).
const String repository = 'mozilla-firefox/firefox';

/// Schema path to its SHA-256 at [pinnedRevision], measured 2026-09-02.
const Map<String, String> pinnedHashes = <String, String>{
  'toolkit/components/extensions/schemas/runtime.json':
      '9aae6d3fcb5c361f6b61a68839ad04a18700edc4601f47a94e684a8cec62d4af',
  'toolkit/components/extensions/schemas/storage.json':
      'ff27a50c99cd90c8ed9395fc18e17fb07cbac8bfa5f3e209147892a858aa67bb',
  'toolkit/components/extensions/schemas/web_request.json':
      '05bd941e5aa3c5acf2f1036476ee12c4259f47a5f4b9986af5e23951fbe538d6',
  'toolkit/components/extensions/schemas/scripting.json':
      '48f8b7c3184d90ae18b98f1ddb387399f890f62f2dc2408305902105b6825fdd',
  'toolkit/components/extensions/schemas/permissions.json':
      '01076d616d84f7e685ff0fc80d4780c867ebf35e0dcb41e700e73c369535b506',
  'toolkit/components/extensions/schemas/alarms.json':
      '5b8c5c04967951e173b57c51e1e7b40378da117153e52ceab502c58eca3d5170',
  'toolkit/components/extensions/schemas/browser_action.json':
      '5f463dbea3859d49113dc55a9870281539f5ab301b31bb8dfa27ccb9f9648587',
  'browser/components/extensions/schemas/tabs.json':
      'dd4a2b611d4e5fd41de615ffef419b2629969a5cc767b054e584ca5f552ffa01',
};

const Duration _timeout = Duration(seconds: 30);
const int _maxBytes = 4 * 1024 * 1024;

Future<void> main() async {
  final client = HttpClient()..connectionTimeout = _timeout;
  var failures = 0;
  try {
    // Negative control first: a run whose source answers everything
    // cannot prove anything (see the library comment).
    final controlStatus = await _statusOf(
      client,
      Uri.https('raw.githubusercontent.com',
          '/$repository/$pinnedRevision/does-not-exist-4711.json'),
    );
    if (controlStatus != 404) {
      stderr.writeln('FEHLER: Negativkontrolle antwortete $controlStatus '
          'statt 404 -- Quelle unglaubwuerdig, Lauf ungueltig.');
      exitCode = 2;
      return;
    }
    stdout.writeln('Negativkontrolle: 404 wie erwartet.');

    for (final entry in pinnedHashes.entries) {
      final uri = Uri.https('raw.githubusercontent.com',
          '/$repository/$pinnedRevision/${entry.key}');
      final bytes = await _fetch(client, uri);
      if (bytes == null) {
        stderr.writeln('FEHLER: ${entry.key} nicht ladbar.');
        failures += 1;
        continue;
      }
      final actual = await _sha256Of(bytes);
      if (actual == entry.value) {
        stdout.writeln('ok      ${entry.key}');
      } else {
        stderr.writeln('DRIFT   ${entry.key}\n'
            '        gepinnt  ${entry.value}\n'
            '        geladen  $actual');
        failures += 1;
      }
    }

    final head = await _headSha(client);
    if (head == null) {
      stdout.writeln('Head-Info: nicht ermittelbar (nur informativ).');
    } else if (head == pinnedRevision) {
      stdout.writeln('Head-Info: Pin ist noch der Branch-Head.');
    } else {
      stdout.writeln('Head-Info: Branch-Head ist inzwischen $head '
          '(nur informativ; unveraenderte Hashes heissen kein Drift).');
    }
  } finally {
    client.close(force: true);
  }
  if (failures > 0) {
    stderr.writeln('$failures von ${pinnedHashes.length} Dateien rot.');
    exitCode = 1;
  } else {
    stdout.writeln('Alle ${pinnedHashes.length} Schema-Hashes stimmen.');
  }
}

/// SHA-256 over [bytes], through the system tool: the project takes no
/// crypto dependency for a development-machine integrity check
/// (SEC-003), and hand-rolling a digest is off the table (SEC-004).
/// macOS ships `shasum`; Linux ships `sha256sum` (PIT-008: the NAMES
/// differ per platform, so both are tried and the output field is
/// normalised).
Future<String> _sha256Of(List<int> bytes) async {
  for (final command in const [
    ['shasum', '-a', '256'],
    ['sha256sum'],
  ]) {
    try {
      final process = await Process.start(command.first, command.sublist(1));
      process.stdin.add(bytes);
      await process.stdin.close();
      final out = await process.stdout.transform(utf8.decoder).join();
      final code = await process.exitCode;
      if (code == 0 && out.trim().isNotEmpty) {
        return out.trim().split(RegExp(r'\s+')).first;
      }
    } on ProcessException {
      continue;
    }
  }
  throw StateError('kein SHA-256-Werkzeug gefunden (shasum/sha256sum)');
}

Future<int> _statusOf(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri).timeout(_timeout);
  final response = await request.close().timeout(_timeout);
  await response.drain<void>();
  return response.statusCode;
}

Future<List<int>?> _fetch(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri).timeout(_timeout);
  final response = await request.close().timeout(_timeout);
  if (response.statusCode != 200) {
    await response.drain<void>();
    return null;
  }
  final bytes = <int>[];
  await for (final chunk in response.timeout(_timeout)) {
    bytes.addAll(chunk);
    if (bytes.length > _maxBytes) {
      throw StateError('Antwort groesser als $_maxBytes Bytes: $uri');
    }
  }
  return bytes;
}

Future<String?> _headSha(HttpClient client) async {
  try {
    final request = await client
        .getUrl(Uri.https('api.github.com', '/repos/$repository/commits/main'))
        .timeout(_timeout);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    return (jsonDecode(body) as Map<String, dynamic>)['sha'] as String?;
  } on Object {
    return null;
  }
}
