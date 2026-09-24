class MovieItem {
  const MovieItem({
    required this.fileName,
    required this.fullPath,
    required this.duration,
    required this.resolution,
    required this.audioTracks,
    required this.subtitleTracks,
    this.audioTrackNames = const <String>[],
    this.subtitleTrackNames = const <String>[],
  });

  final String fileName;
  final String fullPath;
  final Duration duration;
  final String resolution;
  final int audioTracks;
  final int subtitleTracks;
  final List<String> audioTrackNames;
  final List<String> subtitleTrackNames;
}

const demoMovies = <MovieItem>[
  MovieItem(
    fileName: 'Alien.1979.Directors.Cut.mkv',
    fullPath: r'D:\Movies\Alien.1979.Directors.Cut.mkv',
    duration: Duration(hours: 1, minutes: 56, seconds: 34),
    resolution: '1920×1080',
    audioTracks: 3,
    subtitleTracks: 5,
    audioTrackNames: ['Русский 5.1', 'English 5.1', 'Commentary'],
    subtitleTrackNames: [
      'Выкл',
      'Русские',
      'English',
      'Русские форсированные',
      'English SDH',
      'Commentary',
    ],
  ),
  MovieItem(
    fileName: 'Dune.2021.2160p.HEVC.mkv',
    fullPath: r'D:\Movies\Dune.2021.2160p.HEVC.mkv',
    duration: Duration(hours: 2, minutes: 35, seconds: 26),
    resolution: '3840×2160',
    audioTracks: 4,
    subtitleTracks: 8,
    audioTrackNames: ['Русский 5.1', 'English Atmos', 'Deutsch 5.1', 'Commentary'],
    subtitleTrackNames: ['Выкл', 'Русские', 'English', 'Deutsch'],
  ),
  MovieItem(
    fileName: 'Interstellar.2014.2160p.mkv',
    fullPath: r'D:\Movies\Interstellar.2014.2160p.mkv',
    duration: Duration(hours: 2, minutes: 49, seconds: 3),
    resolution: '3840×2160',
    audioTracks: 3,
    subtitleTracks: 6,
    audioTrackNames: ['Русский 5.1', 'English DTS-HD', 'Deutsch 5.1'],
    subtitleTrackNames: ['Выкл', 'Русские', 'English', 'Deutsch'],
  ),
  MovieItem(
    fileName: 'The.Matrix.1999.mkv',
    fullPath: r'D:\Movies\The.Matrix.1999.mkv',
    duration: Duration(hours: 2, minutes: 16, seconds: 17),
    resolution: '1920×1080',
    audioTracks: 2,
    subtitleTracks: 4,
    audioTrackNames: ['Русский 5.1', 'English 5.1'],
    subtitleTrackNames: ['Выкл', 'Русские', 'English'],
  ),
];
