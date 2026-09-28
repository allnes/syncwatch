import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Prevents Windows' default Communications ducking from attenuating audio
/// sessions that were already active when a SyncWatch call starts.
///
/// This does not change the global Windows Communications setting and does not
/// change another application's volume. It temporarily opts the active render
/// sessions out of system ducking, then restores the default preference when
/// the call ends.
class WindowsDuckingGuard {
  final List<IAudioSessionControl2> _protectedSessions = <IAudioSessionControl2>[];

  Future<void> protectActiveRenderSessions() async {
    if (!Platform.isWindows || _protectedSessions.isNotEmpty) return;

    IMMDeviceEnumerator? deviceEnumerator;
    IMMDevice? device;
    IAudioSessionManager2? sessionManager;
    IAudioSessionEnumerator? sessions;

    try {
      // Flutter's Windows runner has COM initialized already.
      deviceEnumerator = createInstance<IMMDeviceEnumerator>(MMDeviceEnumerator);
      device = deviceEnumerator.getDefaultAudioEndpoint(eRender, eMultimedia);
      sessionManager = device!.activate<IAudioSessionManager2>(
        CLSCTX_ALL,
        null,
      );
      sessions = sessionManager!.getSessionEnumerator();

      final currentPid = pid;
      final count = sessions!.getCount();
      for (var index = 0; index < count; index++) {
        final session = sessions!.getSession(index);
        if (session == null) continue;

        IAudioSessionControl2? control;
        try {
          control = session.queryInterface<IAudioSessionControl2>();
          if (control.getState() != AudioSessionStateActive ||
              control.getProcessId() == currentPid) {
            control.release();
            continue;
          }
          control.setDuckingPreference(true);
          _protectedSessions.add(control);
        } catch (error) {
          control?.release();
          debugPrint(
            '[SyncWatch][CALL] DUCKING session opt-out failed: $error',
          );
        } finally {
          session.release();
        }
      }
      debugPrint(
        '[SyncWatch][CALL] DUCKING protected sessions=${_protectedSessions.length}',
      );
    } catch (error) {
      debugPrint('[SyncWatch][CALL] DUCKING guard failed: $error');
    } finally {
      sessions?.release();
      sessionManager?.release();
      device?.release();
      deviceEnumerator?.release();
    }
  }

  Future<void> restore() async {
    if (!Platform.isWindows) return;
    for (final session in _protectedSessions) {
      try {
        session.setDuckingPreference(false);
      } catch (error) {
        debugPrint(
          '[SyncWatch][CALL] DUCKING restore failed: $error',
        );
      } finally {
        session.release();
      }
    }
    if (_protectedSessions.isNotEmpty) {
      debugPrint(
        '[SyncWatch][CALL] DUCKING restored sessions=${_protectedSessions.length}',
      );
    }
    _protectedSessions.clear();
  }
}
