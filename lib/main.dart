import 'package:flutter/material.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const mockMode = bool.fromEnvironment('SYNCWATCH_MOCK', defaultValue: true);
  final controller = AppController();
  await controller.load();

  runApp(
    SyncWatchApp(
      mockMode: mockMode,
      controller: controller,
    ),
  );
}
