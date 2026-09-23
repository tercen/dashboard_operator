import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The version lives in pubspec.yaml; `flutter build web` copies it into
// build/web/version.json, which is what an install serves. build/web is built
// and committed by hand, so a bump without a rebuild leaves the two apart.
String pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.substring('version:'.length).trim();
}

String servedVersion() {
  final json = jsonDecode(File('build/web/version.json').readAsStringSync())
      as Map<String, dynamic>;
  return json['version'] as String;
}

void main() {
  test('pubspec version is a plain semver release', () {
    expect(pubspecVersion(), matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test(
    'build/web/version.json serves the pubspec version',
    () {
      expect(servedVersion(), pubspecVersion());
    },
    // The committed build/web predates WP11. README "Release and upgrade",
    // Procedure step 2 rebuilds it and step 3 deletes this skip.
    skip: 'committed build/web predates WP11; README "Release and upgrade", '
        'step 2 rebuilds it and step 3 ("Lift the version check") removes '
        'this skip',
  );
}
