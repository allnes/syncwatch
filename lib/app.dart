import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_strings.dart';
import 'core/app_theme.dart';
import 'screens/library_screen.dart';

class AppController extends ChangeNotifier {
  Locale locale = const Locale('en');
  String libraryPath = r'D:\Movies';
  String syncServer = 'syncplay.pl:8997';
  String roomName = 'nevermore';
  String username = 'Alex';
  String themeMode = 'dark';

  int skipSeconds = 10;
  bool ducking = false;
  bool scanSubfolders = true;
  bool automaticRefresh = false;
  bool timelinePreview = true;
  double subtitleFontSize = 30.0;
  String subtitlePosition = 'bottom';
  double subtitleVerticalOffset = 0.0;
  String subtitleFontFamily = 'Segoe UI';
  int subtitleTextColorValue = 0xFFFFFFFF;
  int subtitleOutlineColorValue = 0xFF000000;
  double subtitleOutlineWidth = 2.0;
  double subtitleEdgePadding = 20.0;

  double videoBrightness = 0.0;
  double videoContrast = 0.0;
  double videoSaturation = 0.0;
  double videoHue = 0.0;

  double movieVolume = 0.50;
  double callVolume = 0.80;
  double defaultMovieVolume = 0.50;
  bool rememberMovieVolume = true;
  bool normalizeAudio = false;

  bool smoothScaling = true;
  bool hideCursorFullscreen = true;
  double previewCacheMb = 200.0;
  String callInputDevice = 'system';
  String callOutputDevice = 'system';

  String activeMoviePath = '';
  double activeMoviePositionSeconds = 0;
  bool activeMovieSessionStarted = false;

  SharedPreferences? _prefs;

  String t(String key) => AppStrings.get(locale.languageCode, key);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    locale = Locale(_prefs?.getString('language') ?? 'en');
    libraryPath = _prefs?.getString('libraryPath') ?? libraryPath;
    syncServer = _prefs?.getString('syncServer') ?? syncServer;
    roomName = _prefs?.getString('roomName') ?? roomName;
    username = _prefs?.getString('username') ?? username;
    themeMode = _prefs?.getString('themeMode') ?? themeMode;

    skipSeconds = _prefs?.getInt('skipSeconds') ?? skipSeconds;
    ducking = _prefs?.getBool('ducking') ?? ducking;
    scanSubfolders = _prefs?.getBool('scanSubfolders') ?? scanSubfolders;
    automaticRefresh =
        _prefs?.getBool('automaticRefresh') ?? automaticRefresh;
    timelinePreview =
        _prefs?.getBool('timelinePreview') ?? timelinePreview;
    subtitleFontSize =
        _prefs?.getDouble('subtitleFontSize') ?? subtitleFontSize;
    subtitlePosition =
        _prefs?.getString('subtitlePosition') ?? subtitlePosition;
    subtitleVerticalOffset =
        _prefs?.getDouble('subtitleVerticalOffset') ?? subtitleVerticalOffset;
    subtitleFontFamily =
        _prefs?.getString('subtitleFontFamily') ?? subtitleFontFamily;
    subtitleTextColorValue =
        _prefs?.getInt('subtitleTextColorValue') ?? subtitleTextColorValue;
    subtitleOutlineColorValue =
        _prefs?.getInt('subtitleOutlineColorValue') ?? subtitleOutlineColorValue;
    subtitleOutlineWidth =
        _prefs?.getDouble('subtitleOutlineWidth') ?? subtitleOutlineWidth;
    subtitleEdgePadding =
        _prefs?.getDouble('subtitleEdgePadding') ?? subtitleEdgePadding;
    videoBrightness =
        _prefs?.getDouble('videoBrightness') ?? videoBrightness;
    videoContrast =
        _prefs?.getDouble('videoContrast') ?? videoContrast;
    videoSaturation =
        _prefs?.getDouble('videoSaturation') ?? videoSaturation;
    videoHue =
        _prefs?.getDouble('videoHue') ?? videoHue;
    movieVolume = _prefs?.getDouble('movieVolume') ?? movieVolume;
    callVolume = _prefs?.getDouble('callVolume') ?? callVolume;
    defaultMovieVolume =
        _prefs?.getDouble('defaultMovieVolume') ?? defaultMovieVolume;
    rememberMovieVolume =
        _prefs?.getBool('rememberMovieVolume') ?? rememberMovieVolume;
    if (!rememberMovieVolume) {
      movieVolume = defaultMovieVolume;
    }
    normalizeAudio =
        _prefs?.getBool('normalizeAudio') ?? normalizeAudio;
    smoothScaling =
        _prefs?.getBool('smoothScaling') ?? smoothScaling;
    hideCursorFullscreen =
        _prefs?.getBool('hideCursorFullscreen') ?? hideCursorFullscreen;
    previewCacheMb =
        _prefs?.getDouble('previewCacheMb') ?? previewCacheMb;
    callInputDevice = _prefs?.getString('callInputDevice') ?? callInputDevice;
    callOutputDevice = _prefs?.getString('callOutputDevice') ?? callOutputDevice;
    activeMoviePath = _prefs?.getString('activeMoviePath') ?? '';
    activeMoviePositionSeconds =
        _prefs?.getDouble('activeMoviePositionSeconds') ?? 0;
    // "Continue watching" describes the active app session only.
    // A previous application run must not make the button say Continue.
    activeMovieSessionStarted = false;
  }

  Future<void> _setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  Future<void> _setBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  Future<void> _setInt(String key, int value) async {
    await _prefs?.setInt(key, value);
  }

  Future<void> _setDouble(String key, double value) async {
    await _prefs?.setDouble(key, value);
  }

  void setLanguage(String languageCode) {
    locale = Locale(languageCode);
    _setString('language', languageCode);
    notifyListeners();
  }

  void setThemeMode(String value) {
    themeMode = value;
    _setString('themeMode', value);
    notifyListeners();
  }

  ThemeMode get materialThemeMode {
    return switch (themeMode) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  void setLibraryPath(String value) {
    libraryPath = value;
    _setString('libraryPath', value);
    notifyListeners();
  }

  void setSkipSeconds(int value) {
    skipSeconds = value;
    _setInt('skipSeconds', value);
    notifyListeners();
  }

  void setDucking(bool value) {
    ducking = value;
    _setBool('ducking', value);
    notifyListeners();
  }

  void setScanSubfolders(bool value) {
    scanSubfolders = value;
    _setBool('scanSubfolders', value);
    notifyListeners();
  }

  void setAutomaticRefresh(bool value) {
    automaticRefresh = value;
    _setBool('automaticRefresh', value);
    notifyListeners();
  }

  void setTimelinePreview(bool value) {
    timelinePreview = value;
    _setBool('timelinePreview', value);
    notifyListeners();
  }

  void setSubtitleFontSize(double value) {
    subtitleFontSize = value.clamp(18.0, 48.0).toDouble();
    _setDouble('subtitleFontSize', subtitleFontSize);
    notifyListeners();
  }

  void setSubtitlePosition(String value) {
    subtitlePosition = value;
    _setString('subtitlePosition', value);
    notifyListeners();
  }

  void setSubtitleVerticalOffset(double value) {
    subtitleVerticalOffset = value.clamp(-120.0, 120.0).toDouble();
    _setDouble('subtitleVerticalOffset', subtitleVerticalOffset);
    notifyListeners();
  }

  void setSubtitleFontFamily(String value) {
    subtitleFontFamily = value;
    _setString('subtitleFontFamily', value);
    notifyListeners();
  }

  void setSubtitleTextColorValue(int value) {
    subtitleTextColorValue = value;
    _setInt('subtitleTextColorValue', value);
    notifyListeners();
  }

  void setSubtitleOutlineColorValue(int value) {
    subtitleOutlineColorValue = value;
    _setInt('subtitleOutlineColorValue', value);
    notifyListeners();
  }

  void setSubtitleOutlineWidth(double value) {
    subtitleOutlineWidth = value.clamp(0.0, 4.0).toDouble();
    _setDouble('subtitleOutlineWidth', subtitleOutlineWidth);
    notifyListeners();
  }

  void setSubtitleEdgePadding(double value) {
    subtitleEdgePadding = value.clamp(0.0, 80.0).toDouble();
    _setDouble('subtitleEdgePadding', subtitleEdgePadding);
    notifyListeners();
  }

  void setVideoBrightness(double value) {
    videoBrightness = value.clamp(-1.0, 1.0).toDouble();
    _setDouble('videoBrightness', videoBrightness);
    notifyListeners();
  }

  void setVideoContrast(double value) {
    videoContrast = value.clamp(-1.0, 1.0).toDouble();
    _setDouble('videoContrast', videoContrast);
    notifyListeners();
  }

  void setVideoSaturation(double value) {
    videoSaturation = value.clamp(-1.0, 1.0).toDouble();
    _setDouble('videoSaturation', videoSaturation);
    notifyListeners();
  }

  void setVideoHue(double value) {
    videoHue = value.clamp(-180.0, 180.0).toDouble();
    _setDouble('videoHue', videoHue);
    notifyListeners();
  }

  void setDefaultMovieVolume(double value) {
    defaultMovieVolume = value.clamp(0.0, 1.0).toDouble();
    _setDouble('defaultMovieVolume', defaultMovieVolume);
    notifyListeners();
  }

  void setRememberMovieVolume(bool value) {
    rememberMovieVolume = value;
    _setBool('rememberMovieVolume', value);
    notifyListeners();
  }

  void setNormalizeAudio(bool value) {
    normalizeAudio = value;
    _setBool('normalizeAudio', value);
    notifyListeners();
  }

  void setSmoothScaling(bool value) {
    smoothScaling = value;
    _setBool('smoothScaling', value);
    notifyListeners();
  }

  void setHideCursorFullscreen(bool value) {
    hideCursorFullscreen = value;
    _setBool('hideCursorFullscreen', value);
    notifyListeners();
  }

  void setPreviewCacheMb(double value) {
    previewCacheMb = value.clamp(50.0, 500.0).toDouble();
    _setDouble('previewCacheMb', previewCacheMb);
    notifyListeners();
  }

  void resetPlaybackSettings() {
    skipSeconds = 10;
    timelinePreview = true;
    _setInt('skipSeconds', skipSeconds);
    _setBool('timelinePreview', timelinePreview);
    notifyListeners();
  }

  void resetSubtitleSettings() {
    subtitleFontSize = 30.0;
    subtitlePosition = 'bottom';
    subtitleVerticalOffset = 0.0;
    subtitleFontFamily = 'Segoe UI';
    subtitleTextColorValue = 0xFFFFFFFF;
    subtitleOutlineColorValue = 0xFF000000;
    subtitleOutlineWidth = 2.0;
    subtitleEdgePadding = 20.0;
    _setDouble('subtitleFontSize', subtitleFontSize);
    _setString('subtitlePosition', subtitlePosition);
    _setDouble('subtitleVerticalOffset', subtitleVerticalOffset);
    _setString('subtitleFontFamily', subtitleFontFamily);
    _setInt('subtitleTextColorValue', subtitleTextColorValue);
    _setInt('subtitleOutlineColorValue', subtitleOutlineColorValue);
    _setDouble('subtitleOutlineWidth', subtitleOutlineWidth);
    _setDouble('subtitleEdgePadding', subtitleEdgePadding);
    notifyListeners();
  }

  void resetVideoSettings() {
    videoBrightness = 0.0;
    videoContrast = 0.0;
    videoSaturation = 0.0;
    videoHue = 0.0;
    _setDouble('videoBrightness', videoBrightness);
    _setDouble('videoContrast', videoContrast);
    _setDouble('videoSaturation', videoSaturation);
    _setDouble('videoHue', videoHue);
    notifyListeners();
  }

  void resetAudioSettings() {
    defaultMovieVolume = 0.50;
    rememberMovieVolume = true;
    normalizeAudio = false;
    _setDouble('defaultMovieVolume', defaultMovieVolume);
    _setBool('rememberMovieVolume', rememberMovieVolume);
    _setBool('normalizeAudio', normalizeAudio);
    notifyListeners();
  }

  void resetAdvancedPlayerSettings() {
    smoothScaling = true;
    hideCursorFullscreen = true;
    previewCacheMb = 200.0;
    _setBool('smoothScaling', smoothScaling);
    _setBool('hideCursorFullscreen', hideCursorFullscreen);
    _setDouble('previewCacheMb', previewCacheMb);
    notifyListeners();
  }

  void setMovieVolume(double value) {
    movieVolume = value.clamp(0.0, 1.0).toDouble();
    if (rememberMovieVolume) {
      _setDouble('movieVolume', movieVolume);
    }
    notifyListeners();
  }

  void setCallVolume(double value) {
    callVolume = value.clamp(0.0, 1.0).toDouble();
    _setDouble('callVolume', callVolume);
    notifyListeners();
  }

  void setCallInputDevice(String value) {
    callInputDevice = value;
    _setString('callInputDevice', value);
    notifyListeners();
  }

  void setCallOutputDevice(String value) {
    callOutputDevice = value;
    _setString('callOutputDevice', value);
    notifyListeners();
  }

  bool hasPlaybackSessionFor(String moviePath) {
    return activeMovieSessionStarted &&
        activeMoviePath == moviePath &&
        moviePath.isNotEmpty;
  }

  double playbackPositionFor(String moviePath) {
    return hasPlaybackSessionFor(moviePath)
        ? activeMoviePositionSeconds
        : 0;
  }

  void beginPlaybackSession(String moviePath) {
    final changed = activeMoviePath != moviePath;
    activeMoviePath = moviePath;
    if (changed) {
      activeMoviePositionSeconds = 0;
    }
    activeMovieSessionStarted = true;
    _setString('activeMoviePath', activeMoviePath);
    _setDouble('activeMoviePositionSeconds', activeMoviePositionSeconds);
    notifyListeners();
  }

  void endPlaybackSession() {
    activeMoviePath = '';
    activeMoviePositionSeconds = 0;
    activeMovieSessionStarted = false;
    _setString('activeMoviePath', '');
    _setDouble('activeMoviePositionSeconds', 0);
    notifyListeners();
  }

  void updatePlaybackPosition(
    String moviePath,
    double seconds, {
    bool persist = false,
  }) {
    activeMoviePath = moviePath;
    activeMoviePositionSeconds = seconds < 0 ? 0 : seconds;
    if (persist) {
      _setString('activeMoviePath', activeMoviePath);
      _setDouble('activeMoviePositionSeconds', activeMoviePositionSeconds);
      notifyListeners();
    }
  }

  void setSyncServer(String value) {
    syncServer = value;
    _setString('syncServer', value);
    notifyListeners();
  }

  void setRoomName(String value) {
    roomName = value;
    _setString('roomName', value);
    notifyListeners();
  }

  void setUsername(String value) {
    username = value;
    _setString('username', value);
    notifyListeners();
  }
}

class SyncWatchApp extends StatelessWidget {
  const SyncWatchApp({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SyncWatch',
          locale: controller.locale,
          supportedLocales: const [Locale('en'), Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildSyncWatchTheme(Brightness.light),
          darkTheme: buildSyncWatchTheme(Brightness.dark),
          themeMode: controller.materialThemeMode,
          home: LibraryScreen(controller: controller),
        );
      },
    );
  }
}
