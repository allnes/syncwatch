import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/widgets/call_window_surface.dart';

void main() {
  for (final size in [const Size(300, 210), const Size(1280, 720)]) {
    testWidgets('video does not intercept call controls at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final actions = <String>[];
      var microphone = true;
      var camera = true;
      var pinned = false;
      var fullscreen = size.width > 340;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return CallWindowSurface(
              microphoneEnabled: microphone,
              cameraEnabled: camera,
              fullscreen: fullscreen,
              alwaysOnTop: pinned,
              video: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => actions.add('video'),
                child: const ColoredBox(color: Colors.black),
              ),
              onDrag: () => actions.add('drag'),
              onPin: () => setState(() => pinned = !pinned),
              onMinimize: () => actions.add('minimize'),
              onFullscreen: () => setState(() => fullscreen = !fullscreen),
              onMicrophone: () => setState(() => microphone = !microphone),
              onCamera: () => setState(() => camera = !camera),
              onHangUp: () => actions.add('hangup'),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Выключить микрофон'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Включить микрофон'), findsOneWidget);
      await tester.tap(find.byTooltip('Выключить камеру'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Включить камеру'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрепить поверх окон'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Открепить от переднего плана'), findsOneWidget);
      await tester.tap(
        find.byIcon(
          fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        ),
      );
      await tester.pumpAndSettle();
      expect(fullscreen, size.width <= 340);
      await tester.tap(find.byTooltip('Свернуть'));
      await tester.tap(find.byTooltip('Завершить звонок'));
      expect(actions, ['minimize', 'hangup']);
      await tester.tapAt(Offset(size.width / 2, size.height / 2));
      expect(actions.last, 'video');
    });
  }
}
