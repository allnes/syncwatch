class MovieItem {
  const MovieItem({
    required this.fileName,
    required this.fullPath,
    required this.duration,
    required this.resolution,
    required this.audioTracks,
    required this.subtitleTracks,
  });

  final String fileName;
  final String fullPath;
  final Duration duration;
  final String resolution;
  final int audioTracks;
  final int subtitleTracks;
}

const demoMovies = <MovieItem>[
  MovieItem(
    fileName: 'Alien.1979.Directors.Cut.mkv',
    fullPath: r'D:\Movies\Alien.1979.Directors.Cut.mkv',
    duration: Duration(hours: 1, minutes: 56),
    resolution: '1920×1080',
    audioTracks: 3,
    subtitleTracks: 5,
  ),
  MovieItem(
    fileName: 'Dune.2021.2160p.HEVC.mkv',
    fullPath: r'D:\Movies\Dune.2021.2160p.HEVC.mkv',
    duration: Duration(hours: 2, minutes: 35),
    resolution: '3840×2160',
    audioTracks: 4,
    subtitleTracks: 8,
  ),
  MovieItem(
    fileName: 'Interstellar.2014.2160p.mkv',
    fullPath: r'D:\Movies\Interstellar.2014.2160p.mkv',
    duration: Duration(hours: 2, minutes: 49),
    resolution: '3840×2160',
    audioTracks: 3,
    subtitleTracks: 6,
  ),
  MovieItem(
    fileName: 'The.Matrix.1999.mkv',
    fullPath: r'D:\Movies\The.Matrix.1999.mkv',
    duration: Duration(hours: 2, minutes: 16),
    resolution: '1920×1080',
    audioTracks: 2,
    subtitleTracks: 4,
  ),
];
