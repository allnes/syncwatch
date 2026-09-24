import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
  double movieVolume = 0.40;
  double callVolume = 0.80;

  String t(String key) => AppStrings.get(locale.languageCode, key);

  void setLanguage(String languageCode) {
    locale = Locale(languageCode);
    notifyListeners();
  }

  void setLibraryPath(String value) {
    libraryPath = value;
    notifyListeners();
  }

  void setSkipSeconds(int value) {
    skipSeconds = value;
    notifyListeners();
  }

  void setAutoReady(bool value) {
    autoReady = value;
    notifyListeners();
  }

  void setDucking(bool value) {
    ducking = value;
    notifyListeners();
  }

  void setScanSubfolders(bool value) {
    scanSubfolders = value;
    notifyListeners();
  }

  void setAutomaticRefresh(bool value) {
    automaticRefresh = value;
    notifyListeners();
  }

  void setMovieVolume(double value) {
    movieVolume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  void setCallVolume(double value) {
    callVolume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  void setSyncServer(String value) => syncServer = value;
  void setRoomName(String value) => roomName = value;
  void setUsername(String value) => username = value;
}

class SyncWatchApp extends StatefulWidget {
  const SyncWatchApp({super.key, required this.mockMode});

  final bool mockMode;

  @override
  State<SyncWatchApp> createState() => _SyncWatchAppState();
}

class _SyncWatchAppState extends State<SyncWatchApp> {
  final AppController controller = AppController();

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
          home: LibraryScreen(
            controller: controller,
            mockMode: widget.mockMode,
          ),
        );
      },
    );
  }
}
