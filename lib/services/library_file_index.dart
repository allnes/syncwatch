import 'dart:io';

/// Relationships within one completed directory listing, before metadata probes.
class LibraryFileIndex {
  final _videoCounts = <String, int>{};
  final _extraDirectories = <String>{};
  final _subtitles = <String, List<String>>{};

  LibraryFileIndex({
    required List<File> videos,
    required List<File> subtitles,
    required List<File> audio,
  }) {
    final videoNames = <String>{};
    for (final video in videos) {
      final directory = _normalizedDirectory(video.parent.path);
      _videoCounts.update(directory, (count) => count + 1, ifAbsent: () => 1);
      videoNames.add(_baseName(video.path));
    }
    for (final files in [subtitles, audio]) {
      for (final file in files) {
        _extraDirectories.add(_normalizedDirectory(file.parent.path));
        _extraDirectories.add(_normalizedDirectory(file.parent.parent.path));
      }
    }
    for (final subtitle in subtitles) {
      final name = _fileName(subtitle.path);
      final lower = name.toLowerCase();
      // Preserve prefix matching, including names with several dots and
      // subtitles in other folders. The old scan did not require colocation.
      for (
        var dot = lower.indexOf('.');
        dot >= 0;
        dot = lower.indexOf('.', dot + 1)
      ) {
        final prefix = lower.substring(0, dot);
        if (videoNames.contains(prefix)) {
          (_subtitles[prefix] ??= []).add(name);
        }
      }
    }
    for (final names in _subtitles.values) {
      names.sort();
    }
  }

  bool isFolderMovie(File video) {
    final directory = _normalizedDirectory(video.parent.path);
    return _videoCounts[directory] == 1 &&
        _extraDirectories.contains(directory);
  }

  List<String> subtitleNamesFor(File video) =>
      List<String>.of(_subtitles[_baseName(video.path)] ?? const []);

  static String _normalizedDirectory(String path) {
    var normalized = Directory(path).absolute.path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static String _baseName(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return (dot < 0 ? name : name.substring(0, dot)).toLowerCase();
  }
}
