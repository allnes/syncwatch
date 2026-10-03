import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncwatch/app.dart';
import 'package:syncwatch/services/library_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.syncwatch/library_access');
  const key = 'libraryFolderBookmark';
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({'libraryPath': '/movies'});
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return 'bookmark';
      return {'path': '/movies', 'data': 'bookmark'};
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  AppController controller({bool macOS = true}) =>
      AppController(libraryAccess: LibraryAccessService(isMacOS: macOS));

  test('picker selection persists access and next load restores it', () async {
    final first = controller();
    await first.load();
    expect(calls, isEmpty); // Legacy path alone grants no permission.
    await first.setSelectedLibraryPath('/movies');
    expect(calls.single.method, 'create');
    expect(calls.single.arguments, '/movies');
    final second = controller();
    await second.load();
    expect(calls.last.method, 'restore');
    expect(calls.last.arguments, 'bookmark');
    expect(second.libraryPath, '/movies');
    first.dispose();
    second.dispose();
  });

  test(
    'manual edits do not create access or restore an older folder',
    () async {
      final first = controller();
      await first.load();
      await first.setSelectedLibraryPath('/movies');
      calls.clear();
      first.setLibraryPath('/typed/path');
      final second = controller();
      await second.load();
      expect(second.libraryPath, '/typed/path');
      expect(calls, isEmpty);
      first.dispose();
      second.dispose();
    },
  );

  test('restoration persists a moved folder and renewed bookmark', () async {
    SharedPreferences.setMockInitialValues({
      'libraryPath': '/movies',
      key: jsonEncode({'path': '/movies', 'data': 'stale'}),
    });
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'path': '/moved/movies', 'data': 'renewed'},
    );
    final app = controller();
    await app.load();
    final prefs = await SharedPreferences.getInstance();
    expect(app.libraryPath, '/moved/movies');
    expect(prefs.getString('libraryPath'), '/moved/movies');
    expect(jsonDecode(prefs.getString(key)!), {
      'path': '/moved/movies',
      'data': 'renewed',
    });
    app.dispose();
  });

  test(
    'revoked bookmark and failed creation preserve the chosen path',
    () async {
      SharedPreferences.setMockInitialValues({
        'libraryPath': '/movies',
        key: jsonEncode({'path': '/movies', 'data': 'revoked'}),
      });
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'library_access');
      });
      final app = controller();
      await app.load();
      expect(app.libraryPath, '/movies');
      await app.setSelectedLibraryPath('/new/movies');
      expect(app.libraryPath, '/new/movies');
      app.dispose();
    },
  );

  test('corrupt bookmark does not interrupt preferences loading', () async {
    SharedPreferences.setMockInitialValues({
      'libraryPath': '/movies',
      'skipSeconds': 20,
      key: '{broken',
    });
    final app = controller();
    await app.load();
    expect(app.libraryPath, '/movies');
    expect(app.skipSeconds, 20);
    expect(calls, isEmpty);
    app.dispose();
  });

  test(
    'other platforms keep path persistence without native access calls',
    () async {
      final app = controller(macOS: false);
      await app.load();
      await app.setSelectedLibraryPath(r'D:\Movies');
      final restarted = controller(macOS: false);
      await restarted.load();
      expect(restarted.libraryPath, r'D:\Movies');
      expect(calls, isEmpty);
      app.dispose();
      restarted.dispose();
    },
  );
}
