// Run against the original and prepared image packages and compare stdout.
// Keep the two output files outside the checkout.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

void main() {
  final hashes = <String>[];
  void record(Uint8List bytes) => hashes.add(sha256.convert(bytes).toString());

  for (final size in [
    [1, 1],
    [2, 3],
    [7, 9],
    [8, 8],
    [9, 7],
    [16, 17],
    [31, 33],
    [63, 65],
  ]) {
    for (final channels in [1, 2, 3, 4]) {
      final bytes = Uint8List.fromList(
        List.generate(
          size[0] * size[1] * channels,
          (i) => ((i * 193) ^ (i >> 3) ^ size[0]) & 255,
        ),
      );
      for (final quality in [1, 25, 50, 90, 100]) {
        for (final chroma in image.JpegChroma.values) {
          // Encoding alpha may update source pixels: use a fresh input.
          final input = image.Image.fromBytes(
            width: size[0],
            height: size[1],
            numChannels: channels,
            bytes: Uint8List.fromList(bytes).buffer,
          );
          record(
            image.JpegEncoder(quality: quality).encode(input, chroma: chroma),
          );
        }
      }
    }
  }

  for (final format in [
    image.Format.uint8,
    image.Format.uint16,
    image.Format.float32,
  ]) {
    for (final palette in [false, true]) {
      if (palette && format != image.Format.uint8) continue;
      for (final channels in [1, 2, 3, 4]) {
        for (final quality in [-1, 1, 30, 90, 100, 120]) {
          // Reuse the encoder to cover internal buffer reset as well.
          final encoder = image.JpegEncoder(quality: quality);
          for (final size in [
            [3, 5],
            [17, 31],
            [64, 33],
          ]) {
            for (final chroma in image.JpegChroma.values) {
              final input = image.Image(
                width: size[0],
                height: size[1],
                numChannels: channels,
                withPalette: palette,
                format: format,
              );
              if (palette) {
                for (var i = 0; i < 256; i++) {
                  input.palette!.setRgba(i, i, (i * 3) % 256, 255 - i, i);
                }
              }
              for (var y = 0; y < input.height; y++) {
                for (var x = 0; x < input.width; x++) {
                  final v = ((x * 197) ^ (y * 91)) & 255;
                  if (palette) {
                    input.setPixelIndex(x, y, v);
                  } else {
                    final scale = format == image.Format.float32
                        ? 1 / 255
                        : format == image.Format.uint16
                        ? 257
                        : 1;
                    input.setPixelRgba(
                      x,
                      y,
                      v * scale,
                      (255 - v) * scale,
                      (v ~/ 2) * scale,
                      ((v * 3) % 256) * scale,
                    );
                  }
                }
              }
              input.backgroundColor = image.ColorRgb8(15, 41, 203);
              record(encoder.encode(input, chroma: chroma));
            }
          }
        }
      }
    }
  }
  stdout.writeln(jsonEncode({'cases': hashes.length, 'sha256': hashes}));
}
