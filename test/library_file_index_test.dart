import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/services/library_file_index.dart';

import 'support/legacy_library_file_lookup.dart';

void main() {
  test(
    'movie bundles require one video and an extra at most one level down',
    () {
      final videos = [File('one/film.mkv'), File('two/film.mkv')];
      final index = LibraryFileIndex(
        videos: videos,
        subtitles: [File('two/extras/deeper/film.srt')],
        audio: [File('one/audio/commentary.flac')],
      );
      expect(index.isFolderMovie(videos[0]), isTrue);
      expect(index.isFolderMovie(videos[1]), isFalse);
      final several = LibraryFileIndex(
        videos: [...videos, File('one/other.mp4')],
        subtitles: [File('one/film.srt')],
        audio: [],
      );
      expect(several.isFolderMovie(videos[0]), isFalse);
    },
  );

  test(
    'subtitles preserve dot prefixes, duplicates, case and cross-folder matches',
    () {
      final videos = [File('one/a.mkv'), File('two/A.B.mp4'), File('.mkv')];
      final index = LibraryFileIndex(
        videos: videos,
        subtitles: [
          File('elsewhere/a.b.en.srt'),
          File('elsewhere/A.RU.srt'),
          File('other/a.b.en.srt'),
          File('ab.srt'),
          File('.en.srt'),
        ],
        audio: [],
      );
      expect(index.subtitleNamesFor(videos[0]), [
        'A.RU.srt',
        'a.b.en.srt',
        'a.b.en.srt',
      ]);
      expect(index.subtitleNamesFor(videos[1]), ['a.b.en.srt', 'a.b.en.srt']);
      expect(index.subtitleNamesFor(videos[2]), ['.en.srt']);
      final names = index.subtitleNamesFor(videos[0])..clear();
      expect(names, isEmpty);
      expect(index.subtitleNamesFor(videos[0]), hasLength(3));
      final empty = index.subtitleNamesFor(File('missing.mkv'))..add('local');
      expect(empty, ['local']);
      expect(index.subtitleNamesFor(File('missing.mkv')), isEmpty);
    },
  );

  test(
    'matches upstream for mixed paths, casing, duplicate names and extras',
    () {
      final random = Random(20261004);
      const parts = [
        'Film',
        'film',
        'A.B',
        'a',
        'Я.Фильм',
        '.hidden',
        '..',
        'UPPER',
        'x',
        'x.y',
      ];
      final legacy = LegacyLibraryFileLookup();
      for (var round = 0; round < 150; round++) {
        String path(String extension) =>
            '${round.isEven ? Directory.current.path : '.'}/'
            '${parts[random.nextInt(parts.length)]}/'
            '${random.nextInt(4) == 0 ? 'extra/' : ''}'
            '${parts[random.nextInt(parts.length)]}$extension';
        final videos = List.generate(20, (_) => File(path('.mkv')));
        final subtitles = List.generate(
          30,
          (_) => File(path(random.nextBool() ? '.en.srt' : '.srt')),
        );
        final audio = List.generate(20, (_) => File(path('.flac')));
        final index = LibraryFileIndex(
          videos: videos,
          subtitles: subtitles,
          audio: audio,
        );
        for (final video in videos) {
          final expected = legacy.lookup(video, videos, subtitles, audio);
          expect(index.isFolderMovie(video), expected.$1, reason: video.path);
          expect(
            index.subtitleNamesFor(video),
            expected.$2,
            reason: video.path,
          );
        }
      }
    },
  );
}
