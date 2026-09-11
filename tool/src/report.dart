// dart-webext -- shared Dart library for browser extensions
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Renders the comparison rows into the Markdown report.
///
/// Pure text building; every input is handed in, nothing is fetched
/// here, and the same inputs render the same report.
library;

import 'compare.dart';

/// What the runtime check against the head of Lusito's branch found.
enum HeadState {
  /// The pinned revision is the branch head.
  pinnedIsHead,

  /// The branch has moved past the pinned revision.
  pinnedIsBehind,

  /// The head could not be fetched; the reason travels separately.
  unavailable,
}

/// Everything the report header states about its inputs.
class ReportMetadata {
  /// Creates the header metadata.
  const ReportMetadata({
    required this.fetchDate,
    required this.chromeSource,
    required this.chromeRevision,
    required this.chromePubSha256,
    required this.firefoxSource,
    required this.firefoxRevision,
    required this.headState,
    required this.headDetail,
    required this.namespaces,
  });

  /// The day both sources were fetched, `YYYY-MM-DD`.
  final String fetchDate;

  /// Human-readable origin of the Chrome side.
  final String chromeSource;

  /// The pinned Chrome revision (git tag).
  final String chromeRevision;

  /// The sha256 pub.dev records for the same package version, as a
  /// cross-reference to `pubspec.lock`.
  final String chromePubSha256;

  /// Human-readable origin of the Firefox side.
  final String firefoxSource;

  /// The pinned Firefox revision (git commit).
  final String firefoxRevision;

  /// Whether the pinned Firefox revision is still the branch head.
  final HeadState headState;

  /// The head commit, or the reason the head could not be fetched.
  final String headDetail;

  /// The compared namespaces, in report order.
  final List<String> namespaces;
}

/// The label each classification carries in the table.
String classificationLabel(SurfaceClassification classification) =>
    switch (classification) {
      SurfaceClassification.chromeOnly => 'chrome-only',
      SurfaceClassification.firefoxOnly => 'firefox-only',
      SurfaceClassification.sameSignature => 'same signature',
      SurfaceClassification.differentSignature => 'different signature',
      SurfaceClassification.undecidable => 'undecidable',
    };

/// Builds the complete Markdown report.
String buildReport({
  required List<ComparisonRow> rows,
  required ReportMetadata metadata,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# Chrome/Firefox extension API surface comparison');
  buffer.writeln();
  buffer.writeln('<!-- GENERATED FILE - do not edit by hand.');
  buffer.writeln('     Regenerate with:');
  buffer.writeln('     dart run tool/compare_extension_surfaces.dart -->');
  buffer.writeln();
  buffer.writeln('## Sources');
  buffer.writeln();
  buffer.writeln('| Side | Source | Revision | Fetched |');
  buffer.writeln('|---|---|---|---|');
  buffer.writeln('| Chrome | ${metadata.chromeSource} | '
      '`${metadata.chromeRevision}` | ${metadata.fetchDate} |');
  buffer.writeln('| Firefox | ${metadata.firefoxSource} | '
      '`${metadata.firefoxRevision}` | ${metadata.fetchDate} |');
  buffer.writeln();
  buffer.writeln(
      'The Chrome revision equals the `chrome_extension` version pinned in '
      '`pubspec.lock` (pub.dev sha256 `${metadata.chromePubSha256}`).');
  buffer.writeln();
  buffer.writeln(switch (metadata.headState) {
    HeadState.pinnedIsHead =>
      'Branch head check at generation time: the pinned Firefox revision '
          'was still the head of the upstream default branch.',
    HeadState.pinnedIsBehind =>
      '**Branch head check at generation time: the upstream default branch '
          'has moved past the pinned Firefox revision** (head was '
          '`${metadata.headDetail}`). This report still compares the pinned '
          'revision; only this notice reflects the head.',
    HeadState.unavailable => '**Branch head check at generation time failed** '
        '(${metadata.headDetail}). Whether the pinned Firefox revision is '
        'still the upstream head is therefore unknown; this report '
        'compares the pinned revision.',
  });
  buffer.writeln();
  buffer.writeln('## What this table does and does not say');
  buffer.writeln();
  buffer
      .writeln('**"Same signature" does not mean "same behavior".** This table '
          'compares declared surfaces only. Whether a call behaves the same in '
          'both browsers is established in the browser proof harness '
          '(`docs/browser-proof-harness.md`), never here. Without that step, '
          'this table must not be read as evidence of compatibility.');
  buffer.writeln();
  buffer.writeln('Further scope limits, so a row is not read as more than '
      'it is:');
  buffer.writeln();
  buffer.writeln('- Only functions and events are compared, per the eight '
      'namespaces of `docs/ARCHITECTURE.md` section 4.2 '
      '(${metadata.namespaces.join(', ')}). Properties and constants are '
      'out of scope.');
  buffer.writeln('- Signature equality covers parameter count, order, '
      'optionality and normalized types. Parameter names are reported in '
      'notes but do not decide equality. Named object types are compared '
      'structurally (fields, one side against the other), not by name; '
      'methods on referenced object types are compared by name only.');
  buffer.writeln('- Deprecation status and documentation are not compared.');
  buffer.writeln('- An `undecidable` verdict means the comparison could not '
      'carry the case and says why. It is never silently folded into '
      '"same" or "different".');
  buffer.writeln();
  buffer.writeln('## Result counts');
  buffer.writeln();
  final counts = <SurfaceClassification, int>{};
  for (final row in rows) {
    counts[row.classification] = (counts[row.classification] ?? 0) + 1;
  }
  buffer.writeln('| Classification | Rows |');
  buffer.writeln('|---|---|');
  for (final classification in SurfaceClassification.values) {
    buffer.writeln('| ${classificationLabel(classification)} | '
        '${counts[classification] ?? 0} |');
  }
  buffer.writeln('| total | ${rows.length} |');
  buffer.writeln();
  buffer.writeln('## Comparison');
  buffer.writeln();
  String? currentNamespace;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.namespace != currentNamespace) {
      currentNamespace = row.namespace;
      buffer.writeln('### ${row.namespace}');
      buffer.writeln();
      buffer.writeln('| Member | Kind | Classification | Note |');
      buffer.writeln('|---|---|---|---|');
    }
    buffer.writeln('| ${row.memberName} | ${row.memberKind} | '
        '${classificationLabel(row.classification)} | '
        '${_escapeCell(row.note)} |');
    if (i + 1 == rows.length || rows[i + 1].namespace != row.namespace) {
      buffer.writeln();
    }
  }
  return buffer.toString();
}

// A note longer than this drowns the table; the leading reasons stay,
// the cut is marked, and the full reason is one tool run away.
const int _maximumNoteLength = 600;

String _escapeCell(String text) {
  var cell = text;
  if (cell.length > _maximumNoteLength) {
    cell = '${cell.substring(0, _maximumNoteLength)} [... note truncated; '
        'rerun the tool and read the row programmatically for the rest]';
  }
  return cell.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
