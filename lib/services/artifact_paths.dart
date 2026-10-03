import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolve the existing ancestor too, so a symlink cannot redirect artifacts
/// back into the checkout. The output itself need not exist yet.
String physicalArtifactPath(String path) {
  var ancestor = p.absolute(path);
  final suffix = <String>[];
  while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    suffix.insert(0, p.basename(ancestor));
    final parent = p.dirname(ancestor);
    if (parent == ancestor) {
      throw FileSystemException('No existing parent', path);
    }
    ancestor = parent;
  }
  final resolved = File(ancestor).resolveSymbolicLinksSync();
  return p.normalize(p.joinAll([resolved, ...suffix]));
}

/// Source copies on validation hosts may not have a .git directory.
Directory? findSyncWatchCheckout(String start) {
  try {
    return _findSyncWatchCheckout(start);
  } on FileSystemException {
    // A signed macOS app may be launched from a checkout it cannot read.
    // Source discovery is optional; never expand sandbox permissions for logs.
    return null;
  }
}

Directory? _findSyncWatchCheckout(String start) {
  var directory = Directory(physicalArtifactPath(start));
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        RegExp(
          r'^name:\s*syncwatch\s*$',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

String externalArtifactPath(String path, {String? repositoryRoot}) {
  final resolved = physicalArtifactPath(path);
  final roots = <String>{
    if (repositoryRoot != null) physicalArtifactPath(repositoryRoot),
    if (Platform.environment['SYNCWATCH_REPOSITORY_ROOT']
        case final String root)
      physicalArtifactPath(root),
  };
  for (final start in [
    Directory.current.path,
    p.dirname(Platform.resolvedExecutable),
    resolved,
    p.dirname(resolved),
  ]) {
    final root = findSyncWatchCheckout(start);
    if (root != null) roots.add(root.path);
  }
  for (final root in roots) {
    if (p.equals(root, resolved) || p.isWithin(root, resolved)) {
      throw ArgumentError(
        'Artifacts must be outside the SyncWatch checkout: $path',
      );
    }
  }
  return resolved;
}

/// Development logs live beside the checkout. Installed/sandboxed clients use
/// the platform temporary directory. All callers in one process share the path.
final Directory runtimeLogDirectory = _runtimeLogDirectory();

Directory _runtimeLogDirectory() {
  final root =
      findSyncWatchCheckout(Directory.current.path) ??
      findSyncWatchCheckout(p.dirname(Platform.resolvedExecutable));
  final requested =
      Platform.environment['SYNCWATCH_LOG_DIRECTORY'] ??
      (root == null
          ? null
          : p.join(
              root.parent.path,
              'artifacts',
              'syncwatch-performance',
              'runtime',
            ));
  if (requested != null) {
    try {
      return Directory(externalArtifactPath(requested))
        ..createSync(recursive: true);
    } on FileSystemException {
      // macOS sandboxed release clients cannot write beside a source checkout.
    } on ArgumentError {
      // An invalid logging override must not prevent the normal UI starting.
    }
  }
  return Directory(
    externalArtifactPath(
      p.join(Directory.systemTemp.path, 'syncwatch-runtime'),
    ),
  )..createSync(recursive: true);
}
