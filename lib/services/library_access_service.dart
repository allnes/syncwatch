import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists only the library folder explicitly chosen in the native picker.
class LibraryAccessService {
  LibraryAccessService({bool? isMacOS})
    : _isMacOS = isMacOS ?? Platform.isMacOS;

  final bool _isMacOS;
  static const _channel = MethodChannel('dev.syncwatch/library_access');
  static const _key = 'libraryFolderBookmark';

  Future<void> remember(SharedPreferences prefs, String path) async {
    if (!_isMacOS) return;
    try {
      final data = await _channel.invokeMethod<String>('create', path);
      if (data != null) {
        await prefs.setString(_key, jsonEncode({'path': path, 'data': data}));
      }
    } catch (error) {
      // A bookmark failure must not prevent using the current picker grant.
      debugPrint('[SyncWatch] Cannot remember library access: $error');
    }
  }

  Future<String> restore(SharedPreferences prefs, String path) async {
    if (!_isMacOS) return path;
    final saved = prefs.getString(_key);
    if (saved == null) return path;
    try {
      final bookmark = jsonDecode(saved) as Map<String, dynamic>;
      // Manually editing the path must not silently select an older folder.
      if (bookmark['path'] != path) return path;
      final result = await _channel.invokeMapMethod<String, String>(
        'restore',
        bookmark['data'] as String,
      );
      if (result == null) return path;
      final resolved = result['path']!;
      final data = result['data']!;
      // A moved folder or stale bookmark is renewed while access is active.
      await prefs.setString(_key, jsonEncode({'path': resolved, 'data': data}));
      if (resolved != path) await prefs.setString('libraryPath', resolved);
      return resolved;
    } catch (error) {
      // Keep the existing path and picker workflow for revoked/missing grants.
      debugPrint('[SyncWatch] Cannot restore library access: $error');
      return path;
    }
  }
}
