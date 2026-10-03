import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncwatch/services/artifact_paths.dart';

void main() {
  late Directory workspace;
  late Directory checkout;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('syncwatch-paths-');
    checkout = Directory(p.join(workspace.path, 'source'))..createSync();
    File(
      p.join(checkout.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: syncwatch\n');
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  test('allows nonexistent external output and a sibling with same prefix', () {
    for (final name in ['artifacts', 'source-results']) {
      final output = p.join(workspace.path, name, 'run', 'stats.jsonl');
      expect(
        externalArtifactPath(output, repositoryRoot: checkout.path),
        physicalArtifactPath(output),
      );
      expect(File(output).existsSync(), isFalse);
    }
  });

  test(
    'rejects checkout root and nested output before creating directories',
    () {
      for (final output in [
        checkout.path,
        p.join(checkout.path, 'new', 'stats.jsonl'),
        p.join(workspace.path, 'artifacts', '..', 'source', 'stats.jsonl'),
      ]) {
        expect(
          () => externalArtifactPath(output, repositoryRoot: checkout.path),
          throwsArgumentError,
        );
      }
      expect(Directory(p.join(checkout.path, 'new')).existsSync(), isFalse);
    },
  );

  test('discovers a copied source tree without Git metadata', () {
    expect(() => externalArtifactPath(checkout.path), throwsArgumentError);
    final output = p.join(checkout.path, 'results', 'stats.jsonl');
    expect(() => externalArtifactPath(output), throwsArgumentError);
  });

  test(
    'rejects output through a link into the checkout',
    () {
      final link = Link(p.join(workspace.path, 'alias'));
      link.createSync(checkout.path);
      try {
        expect(
          () => externalArtifactPath(
            p.join(link.path, 'new', 'stats.jsonl'),
            repositoryRoot: checkout.path,
          ),
          throwsArgumentError,
        );
      } finally {
        link.deleteSync();
      }
    },
    skip: Platform.isWindows
        ? 'Windows junction coverage is in the PowerShell check'
        : false,
  );
}
