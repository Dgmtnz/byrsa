// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:byrsa_restore_onnx/byrsa_restore_onnx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'native_codec.dart';

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
    this.removeIntrusions = false,
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

  /// Whether to erase whatever is holding the page down at the edge.
  ///
  /// Needs no model, so unlike [dewarpModelPath] this is the user's preference
  /// and nothing else. `Preferences.removeIntrusions` says why it is off by
  /// default.
  final bool removeIntrusions;

  /// Longest side the page is processed and stored at.
  ///
  /// 3000 px is roughly 255 dpi across an A4 page, which is enough for OCR of
  /// body text and small print. The cap exists because phone sensors are now
  /// routinely 48 MP and nothing in a document scan benefits from that; it also
  /// costs nothing, since the platform decoder does the scaling.
  final int maxDimension;

  final int jpegQuality;

  /// Decodes an image file to raw RGBA at no more than [maxDimension].
  ///
  /// Returns the platform's own layout, alpha and all, and does not touch it.
  /// Converting to RGB is a loop over every pixel, and every pixel of a 6.8 MP
  /// page on the interface's isolate is roughly a tenth of a second of frozen
  /// screen — so that loop belongs in the isolate that does the rest of the
  /// work, not here.
  Future<({Uint8List rgba, int width, int height})> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);

    // Everything is released in one place, and only once the pixels are out.
    //
    // This used to dispose the descriptor immediately after instantiating the
    // codec, which reads: the descriptor owns the encoded bytes the codec has
    // not read yet. On a desktop nothing noticed. On a phone it segfaulted
    // inside libflutter.so on an `io.worker` thread — signal 11, fault address
    // 0x20, a null dereference with no Dart exception to catch, which took the
    // whole application down every time a page was opened. The buffer was also
    // never released at all.
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = math.max(descriptor.width, descriptor.height);
      final scale = longest > maxDimension ? maxDimension / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );

      final frame = await codec.getNextFrame();
      image = frame.image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw StateError('Could not read the pixels of $path.');
      }
      return (
        rgba: rgba.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
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
    final decoded = await decode(inputPath);
    final decodeTime = watch.elapsed;

    final result = await compute(
      _restoreAndEncode,
      _RestoreRequest(
        pixels: decoded.rgba,
        width: decoded.width,
        height: decoded.height,
        channels: 4,
        outputPath: outputPath,
        quality: jpegQuality,
        filter: filter,
        dewarpModelPath: dewarpModelPath,
        removeIntrusions: removeIntrusions,
        // A background isolate has no platform channel until it is given the
        // root isolate's token. Without this the native encoder is simply
        // unreachable and the Dart one runs, which is correct but slow.
        rootIsolateToken: RootIsolateToken.instance,
      ),
    );

    return RestoreOutcome(
      path: outputPath,
      width: decoded.width,
      height: decoded.height,
      encoder: result.encoder,
      stages: <StageOutcome>[
        StageOutcome(id: 'decode', duration: decodeTime),
        ...result.stages,
      ],
    );
  }

  /// Drops the alpha channel the platform decoder always produces.
  ///
  /// A scan is opaque, and carrying a fourth byte through every later pass
  /// costs a third more memory traffic for nothing. Runs in the isolate.
  static ImageBuffer rgbFromRgba(Uint8List rgba, int width, int height) {
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
    required this.encoder,
  });

  final String path;
  final int width;
  final int height;
  final List<StageOutcome> stages;

  /// Which encoder wrote the file. Part of any timing that is reported.
  final JpegEncoder encoder;

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
    required this.removeIntrusions,
    required this.rootIsolateToken,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final int channels;
  final String outputPath;
  final int quality;
  final PageFilter filter;
  final String? dewarpModelPath;
  final bool removeIntrusions;
  final RootIsolateToken? rootIsolateToken;
}

class _RestoreReply {
  const _RestoreReply(this.stages, this.encoder);

  final List<StageOutcome> stages;
  final JpegEncoder encoder;
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

/// What a page goes through, in an order none of the three stages choose.
///
/// Geometry before light: flattening the page first means the paper-colour
/// estimate is made on a page that is actually flat. Light before the hand:
/// the intrusion detector asks how far a pixel is from the paper, and on a raw
/// capture that estimate is dragged around by the very shadow the hand casts
/// (`intrusion.dart`, D-042).
///
/// A named function rather than a list inside the isolate entry point because
/// this is the only place the wiring can be observed from a test:
/// [ImageIo.restoreFile] cannot run under `flutter test` at all, since
/// `BackgroundIsolateBinaryMessenger.ensureInitialized` in a `compute` isolate
/// fails there with "Callbacks into the Dart VM are currently prohibited".
@visibleForTesting
List<RestoreStage> restoreStages({
  required PageFilter filter,
  required bool removeIntrusions,
  String? dewarpModelPath,
}) =>
    <RestoreStage>[
      if (dewarpModelPath != null) UvdocStage(modelFile: File(dewarpModelPath)),
      const ClassicalStage().withFilter(filter),
      if (removeIntrusions) const IntrusionStage(),
    ];

/// Runs in an isolate: restore, encode, write.
Future<_RestoreReply> _restoreAndEncode(_RestoreRequest request) async {
  final input = request.channels == 4
      ? ImageIo.rgbFromRgba(request.pixels, request.width, request.height)
      : ImageBuffer(
          width: request.width,
          height: request.height,
          channels: request.channels,
          data: request.pixels,
        );

  final pipeline = RestorePipeline(restoreStages(
    filter: request.filter,
    dewarpModelPath: request.dewarpModelPath,
    removeIntrusions: request.removeIntrusions,
  ));
  final restored = await pipeline.run(input);

  final watch = Stopwatch()..start();

  // Always three channels, even for a grayscale page. Measured: handing an
  // encoder a single-channel image still produces a three-component JPEG, and
  // a file twice the size. Expanding it ourselves costs one pass and leaves
  // the chroma flat, which is what JPEG compresses to almost nothing.
  final rgb = _asRgb(restored.image);

  final token = request.rootIsolateToken;
  var encoder = JpegEncoder.dart;
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    final written = await const NativeCodec().encodeJpeg(
      rgb: rgb,
      width: restored.image.width,
      height: restored.image.height,
      path: request.outputPath,
      quality: request.quality,
    );
    if (written != null) encoder = JpegEncoder.native;
  }

  if (encoder == JpegEncoder.dart) {
    // The fallback, and it is a real one: it runs on a platform with no
    // channel, and whenever the native encoder refuses.
    File(request.outputPath).writeAsBytesSync(
      img.encodeJpg(
        img.Image.fromBytes(
          width: restored.image.width,
          height: restored.image.height,
          bytes: rgb.buffer,
          numChannels: 3,
          order: img.ChannelOrder.rgb,
        ),
        quality: request.quality,
      ),
    );
  }

  return _RestoreReply(<StageOutcome>[
    ...restored.outcomes,
    StageOutcome(id: 'encode:${encoder.name}', duration: watch.elapsed),
  ], encoder);
}
