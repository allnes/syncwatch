import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const mockMode = bool.fromEnvironment('SYNCWATCH_MOCK', defaultValue: true);
  runApp(SyncWatchApp(mockMode: mockMode));
}
