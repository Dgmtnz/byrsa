// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

/// Which encoder produced a file.
///
/// Recorded rather than logged, because it is the difference between a page
/// costing a hundred milliseconds and a second, and a benchmark that does not
/// say which one ran is not saying much.
enum JpegEncoder { native, dart }

/// The platform's JPEG encoder, reached through the application's own channel.
///
/// Encoding a 6.8 MP page in pure Dart costs about 900 ms; the encoder already
/// on the device does it in a fraction of that. This is the only thing the
/// application asks the platform for that no package provides.
class NativeCodec {
  const NativeCodec();

  static const MethodChannel _channel = MethodChannel('dev.byrsa/codec');

  /// Encodes interleaved 8-bit RGB and writes it to [path].
  ///
  /// Returns null when the platform cannot do it — an unsupported platform, a
  /// background isolate with no messenger, a refusal from the encoder. The
  /// caller falls back to the Dart encoder, so a failure here costs speed
  /// rather than the scan.
  Future<String?> encodeJpeg({
    required Uint8List rgb,
    required int width,
    required int height,
    required String path,
    int quality = 92,
  }) async {
    try {
      return await _channel
          .invokeMethod<String>('encodeJpeg', <String, Object?>{
        'rgb': rgb,
        'width': width,
        'height': height,
        'path': path,
        'quality': quality,
      });
    } on Object {
      // Deliberately every error, not only PlatformException: this is a
      // fallback path and the point of it is that nothing gets through.
      return null;
    }
  }
}
