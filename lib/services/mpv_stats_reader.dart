import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart';
// media_kit owns platform-specific resolution of its bundled libmpv.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';

/// Bounded, off-UI-thread diagnostics. libmpv's synchronous getters can wait
/// for its playback thread, so wrapping getProperty in a Future is not enough.
class MpvStatsReader {
  MpvStatsReader(this.player, {this.useWorker = true}) {
    player.platform?.release.add(close);
  }

  final Player player;

  /// Retains the synchronous baseline only for the performance harness.
  final bool useWorker;
  Future<Map<String, String>>? _pending;
  bool _closed = false;

  Future<Map<String, String>> read(List<String> names) {
    if (_closed || player.platform is! NativePlayer) {
      return Future.value(const {});
    }
    // Never queue snapshots if the decoder is slower than the sampling period.
    return _pending ??= _read(names).whenComplete(() => _pending = null);
  }

  Future<Map<String, String>> _read(List<String> names) async {
    final handle = await player.handle;
    if (_closed) return const {};
    if (!useWorker) {
      final native = player.platform as NativePlayer;
      return {for (final name in names) name: await native.getProperty(name)};
    }
    return compute(_readProperties, (handle, NativeLibrary.path, names));
  }

  Future<void> close() async {
    _closed = true;
    // Player.dispose invokes this release hook before destroying its handle.
    // A timeout here could free a handle still being read by the worker.
    try {
      await _pending;
    } catch (_) {
      // The read caller receives diagnostics errors; teardown must still release
      // the native handle after the failed worker has finished.
    }
  }
}

Map<String, String> _readProperties((int, String, List<String>) request) {
  final library = mpv.MPV(DynamicLibrary.open(request.$2));
  final handle = Pointer<mpv.mpv_handle>.fromAddress(request.$1);
  final result = <String, String>{};
  for (final name in request.$3) {
    final pointer = name.toNativeUtf8();
    try {
      final value = library.mpv_get_property_string(handle, pointer.cast());
      if (value == nullptr) {
        result[name] = '';
      } else {
        try {
          result[name] = value.cast<Utf8>().toDartString();
        } finally {
          library.mpv_free(value.cast());
        }
      }
    } finally {
      calloc.free(pointer);
    }
  }
  return result;
}
