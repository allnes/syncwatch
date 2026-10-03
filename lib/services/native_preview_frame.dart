import 'dart:ffi';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart';
// media_kit owns resolution of its bundled libmpv on each desktop platform.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';

import 'preview_thumbnail.dart';

/// The caller keeps [player] alive until capture completes, including fallback.
/// Carry native dimensions/stride with the pixels; source metadata may differ
/// from the screenshot after rotation or sample-aspect-ratio correction.
Future<Uint8List?> capturePreviewThumbnail(
  Player player, {
  required int width,
  required int height,
  bool useNativePixels = true,
}) async {
  if (useNativePixels && player.platform is NativePlayer) {
    try {
      final frame = await compute(_capturePixels, (
        await player.handle,
        NativeLibrary.path,
      ));
      if (frame == null) return null;
      return await encodeRawPreviewThumbnail(
        frame.bytes,
        sourceWidth: frame.width,
        sourceHeight: frame.height,
        rowBytes: frame.stride,
        width: width,
        height: height,
      );
    } catch (error) {
      debugPrint('[SyncWatch][PLAYBACK] PREVIEW_CAPTURE_FALLBACK $error');
    }
  }
  final encoded = await player.screenshot(format: 'image/jpeg');
  if (encoded == null || encoded.isEmpty) return null;
  return resizePreviewThumbnail(encoded, width: width, height: height);
}

/// Scale BGRA pixels in the image engine before encoding only the thumbnail.
Future<Uint8List> encodeRawPreviewThumbnail(
  Uint8List pixels, {
  required int sourceWidth,
  required int sourceHeight,
  required int rowBytes,
  required int width,
  required int height,
}) async {
  final scale = math.min(
    1.0,
    math.max(width / sourceWidth, height / sourceHeight),
  );
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: sourceWidth,
      height: sourceHeight,
      rowBytes: rowBytes,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (sourceWidth * scale).ceil()),
      targetHeight: math.max(1, (sourceHeight * scale).ceil()),
    );
    image = (await codec.getNextFrame()).image;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Preview image encoding failed');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

class _Pixels {
  const _Pixels(this.bytes, this.width, this.height, this.stride);
  final Uint8List bytes;
  final int width;
  final int height;
  final int stride;
}

_Pixels? _capturePixels((int, String) request) {
  final library = mpv.MPV(DynamicLibrary.open(request.$2));
  final handle = Pointer<mpv.mpv_handle>.fromAddress(request.$1);
  final command = 'screenshot-raw'.toNativeUtf8();
  final mode = 'video'.toNativeUtf8();
  // Two arguments plus the required null terminator, sized in pointers.
  final arguments = calloc<Pointer<Utf8>>(3);
  final result = calloc<mpv.mpv_node>();
  try {
    arguments[0] = command;
    arguments[1] = mode;
    final status = library.mpv_command_ret(handle, arguments.cast(), result);
    if (status < 0 || result.ref.format != mpv.mpv_format.MPV_FORMAT_NODE_MAP) {
      return null;
    }
    final map = result.ref.u.list.ref;
    int? width, height, stride;
    String? format;
    Uint8List? nativeBytes;
    for (var index = 0; index < map.num; index++) {
      final key = map.keys[index].cast<Utf8>().toDartString();
      final value = map.values[index];
      if (value.format == mpv.mpv_format.MPV_FORMAT_INT64) {
        if (key == 'w') width = value.u.int64;
        if (key == 'h') height = value.u.int64;
        if (key == 'stride') stride = value.u.int64;
      } else if (key == 'format' &&
          value.format == mpv.mpv_format.MPV_FORMAT_STRING) {
        format = value.u.string.cast<Utf8>().toDartString();
      } else if (key == 'data' &&
          value.format == mpv.mpv_format.MPV_FORMAT_BYTE_ARRAY) {
        final data = value.u.ba.ref;
        nativeBytes = data.data.cast<Uint8>().asTypedList(data.size);
      }
    }
    if (width == null ||
        height == null ||
        stride == null ||
        nativeBytes == null ||
        width <= 0 ||
        height <= 0 ||
        stride < width * 4 ||
        nativeBytes.length < stride * height) {
      throw StateError('Invalid native screenshot layout');
    }
    if (format != 'bgr0' && format != 'bgra') {
      throw UnsupportedError('Native screenshot format: $format');
    }
    final bytes = Uint8List.fromList(
      Uint8List.sublistView(nativeBytes, 0, stride * height),
    );
    if (format == 'bgr0') {
      // mpv's unused fourth byte is not alpha. Make the video explicitly opaque.
      for (var index = 3; index < bytes.length; index += 4) {
        bytes[index] = 255;
      }
    }
    return _Pixels(bytes, width, height, stride);
  } finally {
    library.mpv_free_node_contents(result);
    calloc.free(result);
    calloc.free(arguments);
    calloc.free(mode);
    calloc.free(command);
  }
}
