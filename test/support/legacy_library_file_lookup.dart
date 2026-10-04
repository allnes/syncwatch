// Frozen directory/subtitle matching from upstream eee5854.
// Differential oracle: preserve even cross-folder and dotted-name matching.
import 'dart:io';

class LegacyLibraryFileLookup {
  String _normalizedDir(String path) {
    var normalized = Directory(path).absolute.path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  bool _isDirectlyInside(String filePath, String directoryPath) {
    return _normalizedDir(File(filePath).parent.path) == directoryPath;
  }

  bool _isInsideOneChildFolder(String filePath, String directoryPath) {
    final parent = File(filePath).parent;
    final parentPath = _normalizedDir(parent.path);
    if (parentPath == directoryPath) return false;
    return _normalizedDir(parent.parent.path) == directoryPath;
  }

  bool _looksLikeMovieBundle({
    required File videoFile,
    required List<File> allVideos,
    required List<File> subtitleFiles,
    required List<File> audioFiles,
  }) {
    final movieDir = _normalizedDir(videoFile.parent.path);

    final videosInSameFolder = allVideos.where(
      (candidate) => _isDirectlyInside(candidate.path, movieDir),
    );

    if (videosInSameFolder.length != 1) {
      return false;
    }

    bool isRelatedExtra(File extra) {
      return _isDirectlyInside(extra.path, movieDir) ||
          _isInsideOneChildFolder(extra.path, movieDir);
    }

    return subtitleFiles.any(isRelatedExtra) || audioFiles.any(isRelatedExtra);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  String _baseName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? fileName : fileName.substring(0, dot);
  }

  (bool, List<String>) lookup(
    File video,
    List<File> videos,
    List<File> subs,
    List<File> audio,
  ) {
    final base = _baseName(_fileName(video.path)).toLowerCase();
    final matches =
        subs
            .where((s) => _fileName(s.path).toLowerCase().startsWith('$base.'))
            .map((s) => _fileName(s.path))
            .toList()
          ..sort();
    return (
      _looksLikeMovieBundle(
        videoFile: video,
        allVideos: videos,
        subtitleFiles: subs,
        audioFiles: audio,
      ),
      matches,
    );
  }
}
