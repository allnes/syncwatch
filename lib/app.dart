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

  int skipSeconds = 10;
  bool autoReady = true;
  bool ducking = false;
  bool scanSubfolders = true;
  bool automaticRefresh = false;
  bool timelinePreview = true;
  double movieVolume = 0.40;
  double callVolume = 0.80;
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

    skipSeconds = _prefs?.getInt('skipSeconds') ?? skipSeconds;
    autoReady = _prefs?.getBool('autoReady') ?? autoReady;
    ducking = _prefs?.getBool('ducking') ?? ducking;
    scanSubfolders = _prefs?.getBool('scanSubfolders') ?? scanSubfolders;
    automaticRefresh =
        _prefs?.getBool('automaticRefresh') ?? automaticRefresh;
    timelinePreview =
        _prefs?.getBool('timelinePreview') ?? timelinePreview;
    movieVolume = _prefs?.getDouble('movieVolume') ?? movieVolume;
    callVolume = _prefs?.getDouble('callVolume') ?? callVolume;
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

  void setAutoReady(bool value) {
    autoReady = value;
    _setBool('autoReady', value);
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

  void setMovieVolume(double value) {
    movieVolume = value.clamp(0.0, 1.0).toDouble();
    _setDouble('movieVolume', movieVolume);
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
          theme: buildSyncWatchTheme(),
          home: LibraryScreen(controller: controller),
        );
      },
    );
  }
}
