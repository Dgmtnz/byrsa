// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Reading and writing page images, and running restoration off the UI thread.
///
/// Two decisions worth knowing about, both measured rather than assumed:
///
/// **Decoding uses `dart:ui`, not a Dart codec.** A pure-Dart JPEG decode of a
/// 12 MP photograph takes about 1.1 s on a desktop; the platform decoder takes
/// a fraction of that and gives a free downscale on the way, which is also how
/// [maxDimension] is enforced without ever materialising the full image.
///
/// **Restoration and encoding run in an isolate.** Together they are around a
/// second on a desktop and several on a phone. That is a progress bar, not a
/// frozen interface — and the difference is invisible in a benchmark and very
/// visible in the hand.
class ImageIo {
  const ImageIo({
    this.maxDimension = 3000,
    this.jpegQuality = 92,
    this.filter = PageFilter.colour,
    this.dewarpModelPath,
  });

  /// What the restored page should look like.
  final PageFilter filter;

  /// The UVDoc model, when it has been downloaded and the user wants it.
  ///
  /// A path rather than an object because everything downstream runs in an
  /// isolate. Null simply means the stage reports itself unavailable and the
  /// pipeline carries on — which is the whole point of recording a skip rather
  /// than throwing.
  final String? dewarpModelPath;

  /// Longest side the page is processed and stored at.
  ///
  /// 3000 px is roughly 255 dpi across an A4 page, which is enough for OCR of
  /// body text and small print. The cap exists because phone sensors are now
  /// routinely 48 MP and nothing in a document scan benefits from that; it also
  /// costs nothing, since the platform decoder does the scaling.
  final int maxDimension;

  final int jpegQuality;

  /// Decodes an image file into a buffer the restoration can work on.
  Future<ImageBuffer> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);

    final longest = math.max(descriptor.width, descriptor.height);
    final scale = longest > maxDimension ? maxDimension / longest : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    descriptor.dispose();

    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    codec.dispose();

    if (rgba == null) {
      throw StateError('Could not read the pixels of $path.');
    }
    return _rgbFromRgba(rgba.buffer.asUint8List(), width, height);
  }

  /// Restores [inputPath] and writes the result to [outputPath].
  ///
  /// Decoding happens here, where the platform codec lives; everything after it
  /// is pure Dart and runs in an isolate.
  Future<RestoreOutcome> restoreFile({
    required String inputPath,
    required String outputPath,
  }) async {
    final watch = Stopwatch()..start();
    final image = await decode(inputPath);
    final decodeTime = watch.elapsed;

    final result = await compute(
      _restoreAndEncode,
      _RestoreRequest(
        pixels: image.data,
        width: image.width,
        height: image.height,
        channels: image.channels,
        outputPath: outputPath,
        quality: jpegQuality,
        filter: filter,
        dewarpModelPath: dewarpModelPath,
      ),
    );

    return RestoreOutcome(
      path: outputPath,
      width: image.width,
      height: image.height,
      stages: <StageOutcome>[
        StageOutcome(id: 'decode', duration: decodeTime),
        ...result.stages,
      ],
    );
  }

  /// Drops the alpha channel the platform decoder always produces.
  ///
  /// A scan is opaque, and carrying a fourth byte through every later pass
  /// costs a third more memory traffic for nothing.
  static ImageBuffer _rgbFromRgba(Uint8List rgba, int width, int height) {
    final pixels = width * height;
    final rgb = Uint8List(pixels * 3);
    for (var i = 0; i < pixels; i++) {
      rgb[i * 3] = rgba[i * 4];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    return ImageBuffer(width: width, height: height, channels: 3, data: rgb);
  }
}

/// What restoring one page produced, with the timings the harness records.
class RestoreOutcome {
  const RestoreOutcome({
    required this.path,
    required this.width,
    required this.height,
    required this.stages,
  });

  final String path;
  final int width;
  final int height;
  final List<StageOutcome> stages;

  Duration get total =>
      stages.fold(Duration.zero, (sum, stage) => sum + stage.duration);
}

/// Sent to the isolate. Plain fields and typed data, so it travels.
class _RestoreRequest {
  const _RestoreRequest({
    required this.pixels,
    required this.width,
    required this.height,
    required this.channels,
    required this.outputPath,
    required this.quality,
    required this.filter,
    required this.dewarpModelPath,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final int channels;
  final String outputPath;
  final int quality;
  final PageFilter filter;
  final String? dewarpModelPath;
}

class _RestoreReply {
  const _RestoreReply(this.stages);

  final List<StageOutcome> stages;
}

/// Expands a grayscale buffer to RGB, or returns an RGB one untouched.
Uint8List _asRgb(ImageBuffer image) {
  if (!image.isGray) return image.data;
  final out = Uint8List(image.pixelCount * 3);
  for (var i = 0; i < image.pixelCount; i++) {
    final value = image.data[i];
    out[i * 3] = value;
    out[i * 3 + 1] = value;
    out[i * 3 + 2] = value;
  }
  return out;
}

/// Runs in an isolate: restore, encode, write.
Future<_RestoreReply> _restoreAndEncode(_RestoreRequest request) async {
  final input = ImageBuffer(
    width: request.width,
    height: request.height,
    channels: request.channels,
    data: request.pixels,
  );

  final pipeline = RestorePipeline(<RestoreStage>[
    // Geometry before light: flattening the page first means the paper-colour
    // estimate is made on a page that is actually flat.
    if (request.dewarpModelPath != null)
      UvdocStage(modelFile: File(request.dewarpModelPath!)),
    const ClassicalStage().withFilter(request.filter),
  ]);
  final restored = await pipeline.run(input);

  final watch = Stopwatch()..start();
  final encoded = img.encodeJpg(
    img.Image.fromBytes(
      width: restored.image.width,
      height: restored.image.height,
      // Always three channels, even for a grayscale page. Measured: handing
      // the encoder a single-channel image still produces a three-component
      // JPEG, and a file twice the size. Expanding it ourselves costs one
      // pass and leaves the chroma flat, which is what JPEG compresses to
      // almost nothing.
      bytes: _asRgb(restored.image).buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    ),
    quality: request.quality,
  );
  File(request.outputPath).writeAsBytesSync(encoded);

  return _RestoreReply(<StageOutcome>[
    ...restored.outcomes,
    StageOutcome(id: 'encode', duration: watch.elapsed),
  ]);
}
