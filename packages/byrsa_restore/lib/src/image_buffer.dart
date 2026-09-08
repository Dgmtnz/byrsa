// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

/// An 8-bit image in memory, one or three interleaved channels.
///
/// Deliberately not a `dart:ui.Image` and not an OpenCV `Mat`: the restoration
/// maths is pure Dart so it can be unit-tested on a laptop, and so the package
/// does not force a 30 MB native image library on an application that only
/// wants the classical pipeline (DECISIONS.md D-020).
class ImageBuffer {
  ImageBuffer({
    required this.width,
    required this.height,
    required this.channels,
    required this.data,
  }) : assert(channels == 1 || channels == 3, 'grayscale or RGB only') {
    if (data.length != width * height * channels) {
      throw ArgumentError(
        'Expected ${width * height * channels} bytes, got ${data.length}.',
      );
    }
  }

  ImageBuffer.gray(this.width, this.height, Uint8List? data)
      : channels = 1,
        data = data ?? Uint8List(width * height);

  final int width;
  final int height;
  final int channels;
  final Uint8List data;

  int get pixelCount => width * height;
  bool get isGray => channels == 1;

  ImageBuffer copy() => ImageBuffer(
        width: width,
        height: height,
        channels: channels,
        data: Uint8List.fromList(data),
      );

  /// Luma plane, using the Rec. 601 weights.
  Uint8List toLuma() {
    if (isGray) return data;
    final out = Uint8List(pixelCount);
    for (var i = 0; i < pixelCount; i++) {
      final r = data[i * 3];
      final g = data[i * 3 + 1];
      final b = data[i * 3 + 2];
      out[i] = (0.299 * r + 0.587 * g + 0.114 * b).round();
    }
    return out;
  }

  /// Rebuilds the image from a corrected luma plane, keeping the original hue.
  ///
  /// Scaling the channels by the luma ratio rather than replacing them is what
  /// keeps a yellow receipt yellow instead of turning it grey.
  ImageBuffer withLuma(Uint8List luma) {
    if (isGray) {
      return ImageBuffer.gray(width, height, luma);
    }
    final original = toLuma();
    final out = Uint8List(data.length);
    for (var i = 0; i < pixelCount; i++) {
      final before = original[i];
      final ratio = before == 0 ? 1.0 : luma[i] / before;
      for (var c = 0; c < 3; c++) {
        out[i * 3 + c] = (data[i * 3 + c] * ratio).round().clamp(0, 255);
      }
    }
    return ImageBuffer(width: width, height: height, channels: 3, data: out);
  }
}
