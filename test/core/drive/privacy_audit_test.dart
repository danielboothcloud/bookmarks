import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AC6 says zero telemetry / analytics / crash-reporting SDKs are added.
/// The story spec calls out the exact verification command:
///
///   grep -ri "(firebase|sentry|crashlytics|mixpanel|amplitude|
///              appcenter|datadog|posthog|segment)" pubspec.yaml lib/ test/
///
/// must return zero results. This test runs that audit so a future PR
/// that drops one of those SDKs in fails CI instead of slipping past.
void main() {
  const forbidden = <String>[
    'firebase',
    'sentry',
    'crashlytics',
    'mixpanel',
    'amplitude',
    'appcenter',
    'datadog',
    'posthog',
    'segment',
  ];

  // Match the bare name as a word so we don't flag e.g. a comment that
  // happens to contain the substring "amplitudes" or a variable named
  // "segments". Case-insensitive per the AC6 grep.
  final patterns = {
    for (final name in forbidden)
      name: RegExp('\\b$name\\b', caseSensitive: false),
  };

  test('pubspec.yaml declares no telemetry / analytics SDK', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final entry in patterns.entries) {
      expect(
        entry.value.hasMatch(pubspec),
        isFalse,
        reason:
            'pubspec.yaml references "${entry.key}" — AC6 forbids any '
            'telemetry/analytics/crash-reporting SDK. If this is a false '
            'positive (e.g. a transitive dep name collision), tighten the '
            'pattern in privacy_audit_test.dart rather than relaxing AC6.',
      );
    }
  });

  test('lib/ and test/ reference no telemetry SDK names', () {
    final hits = <String>[];
    for (final dirPath in const ['lib', 'test']) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Skip generated files — freezed/json_serializable output names
        // don't include the forbidden words today, but if they ever do
        // (e.g. a model called `SegmentBuilder`), we don't want a false
        // positive failing the audit. Re-enable scanning if you ship
        // generated code that intentionally uses these names.
        if (entity.path.endsWith('.freezed.dart') ||
            entity.path.endsWith('.g.dart') ||
            entity.path.contains('/generated/')) {
          continue;
        }
        // Skip this audit file itself; it deliberately names the SDKs.
        if (entity.path.endsWith('privacy_audit_test.dart')) continue;

        final content = entity.readAsStringSync();
        for (final entry in patterns.entries) {
          if (entry.value.hasMatch(content)) {
            hits.add('${entry.key} -> ${entity.path}');
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Telemetry SDK references found in source — AC6 forbids these. '
          'Hits:\n  ${hits.join("\n  ")}',
    );
  });
}
