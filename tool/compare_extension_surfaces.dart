// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Compares the Chrome and Firefox extension API declaration sources
/// and writes `docs/api-surface-comparison.md`.
///
/// Run from the package root:
///
///     dart run tool/compare_extension_surfaces.dart
///
/// The Chrome side is xvrh's generated `chrome_extension` Dart
/// bindings at the tag matching the version pinned in `pubspec.lock`;
/// the Firefox side is Lusito's generated TypeScript declarations at a
/// revision pinned below. Both sources are fixed here and never taken
/// from input (SEC-012); every fetch has explicit timeouts and a size
/// cap (SEC-006, SEC-011).
///
/// The head of Lusito's default branch is additionally fetched at
/// runtime, but only to say in the report header whether the pinned
/// revision is still the head. The comparison always runs against the
/// pinned revision.
library;

import 'dart:convert';
import 'dart:io';

import 'src/compare.dart';
import 'src/dart_surface_parser.dart';
import 'src/report.dart';
import 'src/surface_model.dart';
import 'src/ts_surface_parser.dart';

/// The eight namespaces of `docs/ARCHITECTURE.md` section 4.2, in
/// report order.
const List<String> _namespaces = [
  'runtime',
  'tabs',
  'storage',
  'webRequest',
  'action',
  'scripting',
  'permissions',
  'alarms',
];

// The pinned revisions. The Chrome tag must match the version pinned
// in pubspec.lock; the tool verifies that before fetching anything.
const String _chromeTag = 'v0.4.0';
const String _firefoxCommit = '58c2b0e4a7310a49109a750d3f4de72443010ffd';

const String _chromeBase =
    'https://raw.githubusercontent.com/xvrh/chrome_extension.dart';
const String _firefoxBase =
    'https://raw.githubusercontent.com/Lusito/webextension-polyfill-ts';
const String _headUrl = 'https://api.github.com/repos/Lusito/'
    'webextension-polyfill-ts/commits/master';

const String _outputPath = 'docs/api-surface-comparison.md';

// The largest of the sixteen files is well under 100 KB; anything
// larger than this is not one of them (SEC-011).
const int _maximumBodyBytes = 2 * 1024 * 1024;

const Duration _fetchTimeout = Duration(seconds: 30);

/// Fetches both pinned sources, compares them and writes [_outputPath].
Future<void> main() async {
  final (pinnedVersion, pubSha256) = _chromePinFromLock();
  if ('v$pinnedVersion' != _chromeTag) {
    _fail('pubspec.lock pins chrome_extension $pinnedVersion, this tool '
        'pins tag $_chromeTag; update one of them before regenerating');
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final chromeSources = <String, String>{};
  final firefoxSources = <String, String>{};
  HeadState headState;
  String headDetail;
  try {
    try {
      for (final namespace in _namespaces) {
        chromeSources[namespace] = await _fetch(client,
            '$_chromeBase/$_chromeTag/lib/${_chromeFileName(namespace)}.dart');
        firefoxSources[namespace] = await _fetch(client,
            '$_firefoxBase/$_firefoxCommit/out/namespaces/$namespace.d.ts');
      }
    } on Exception catch (exception) {
      _fail(exception.toString());
    }
    (headState, headDetail) = await _fetchHeadState(client);
  } finally {
    client.close(force: true);
  }

  final List<ComparisonRow> rows;
  try {
    final chrome = SurfaceCatalog([
      for (final namespace in _namespaces)
        parseChromeNamespace(chromeSources[namespace]!, namespace),
    ]);
    final firefox = SurfaceCatalog([
      for (final namespace in _namespaces)
        parseFirefoxNamespace(firefoxSources[namespace]!, namespace),
    ]);
    rows = compareSurfaces(
      chrome: chrome,
      firefox: firefox,
      namespaces: _namespaces,
    );
  } on FormatException catch (exception) {
    _fail(exception.message);
  }

  final now = DateTime.now();
  final date = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final report = buildReport(
    rows: rows,
    metadata: ReportMetadata(
      fetchDate: date,
      chromeSource:
          'xvrh/chrome_extension.dart, `lib/<namespace>.dart` (generated '
          'Dart bindings, Chrome)',
      chromeRevision: _chromeTag,
      chromePubSha256: pubSha256,
      firefoxSource:
          'Lusito/webextension-polyfill-ts, `out/namespaces/<namespace>.d.ts` '
          '(generated TypeScript declarations, Firefox)',
      firefoxRevision: _firefoxCommit,
      headState: headState,
      headDetail: headDetail,
      namespaces: _namespaces,
    ),
  );
  File(_outputPath).writeAsStringSync(report);

  final counts = <SurfaceClassification, int>{};
  for (final row in rows) {
    counts[row.classification] = (counts[row.classification] ?? 0) + 1;
  }
  stdout.writeln('wrote $_outputPath: ${rows.length} rows ('
      '${SurfaceClassification.values.map((classification) => '${classificationLabel(classification)} ${counts[classification] ?? 0}').join(', ')})');
  stdout.writeln(switch (headState) {
    HeadState.pinnedIsHead =>
      'pinned firefox revision is still the branch head',
    HeadState.pinnedIsBehind =>
      'NOTE: upstream branch head has moved to $headDetail',
    HeadState.unavailable => 'NOTE: head check failed: $headDetail',
  });
}

/// The Chrome-side file name of [namespace] (snake_case).
String _chromeFileName(String namespace) => namespace.replaceAllMapped(
    RegExp('[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');

/// Reads the pinned `chrome_extension` version and pub.dev sha256 from
/// `pubspec.lock`, the single place that pins them (TEST-012).
(String, String) _chromePinFromLock() {
  final lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    _fail('pubspec.lock not found; run from the package root');
  }
  final lines = lock.readAsLinesSync();
  final start = lines.indexWhere((line) => line.trim() == 'chrome_extension:');
  if (start == -1) {
    _fail('pubspec.lock does not pin chrome_extension');
  }
  String? version;
  String? sha256;
  for (var i = start + 1; i < lines.length; i++) {
    // Block lines of this package are indented four spaces or more;
    // the next package entry sits at two.
    if (!lines[i].startsWith('    ')) {
      break;
    }
    final line = lines[i].trim();
    final versionMatch = RegExp(r'^version: "(.+)"$').firstMatch(line);
    if (versionMatch != null) {
      version = versionMatch.group(1);
    }
    final shaMatch = RegExp(r'^sha256: "?([0-9a-f]{64})"?$').firstMatch(line);
    if (shaMatch != null) {
      sha256 = shaMatch.group(1);
    }
  }
  if (version == null || sha256 == null) {
    _fail('pubspec.lock entry for chrome_extension carries no version or '
        'sha256');
  }
  return (version, sha256);
}

/// Fetches [url] with timeouts and the size cap. Throws an
/// [HttpException] on anything unexpected; the caller decides whether
/// that is fatal (source files) or a reported notice (head check).
Future<String> _fetch(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url)).timeout(_fetchTimeout);
  final response = await request.close().timeout(_fetchTimeout);
  if (response.statusCode != 200) {
    throw HttpException('$url answered ${response.statusCode}');
  }
  final bytes = <int>[];
  await response.forEach((chunk) {
    bytes.addAll(chunk);
    if (bytes.length > _maximumBodyBytes) {
      throw HttpException('$url sent more than $_maximumBodyBytes bytes; '
          'that is not one of the declaration files');
    }
  }).timeout(_fetchTimeout);
  if (bytes.isEmpty) {
    throw HttpException('$url answered with an empty body');
  }
  return utf8.decode(bytes);
}

/// Fetches the head commit of Lusito's default branch. Never fatal:
/// the comparison does not depend on it, only the header notice does.
Future<(HeadState, String)> _fetchHeadState(HttpClient client) async {
  try {
    final body = await _fetch(client, _headUrl);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      return (HeadState.unavailable, 'head response is not a JSON object');
    }
    final sha = decoded['sha'];
    if (sha is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
      return (HeadState.unavailable, 'head response carries no commit sha');
    }
    return sha == _firefoxCommit
        ? (HeadState.pinnedIsHead, sha)
        : (HeadState.pinnedIsBehind, sha);
  } on Exception catch (exception) {
    return (HeadState.unavailable, exception.toString());
  }
}

Never _fail(String message) {
  stderr.writeln('compare_extension_surfaces: $message');
  exit(2);
}
