// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'package:byrsa_restore/byrsa_restore.dart';

/// Flattens a curved page, using UVDoc.
///
/// UVDoc is an encoder-decoder from ETH Zurich (SIGGRAPH Asia 2023) that looks
/// at a photograph of a page and says, for every point of the flattened result,
/// where to read from in the original. This stage runs it and hands the answer
/// to [remapThroughGrid].
///
/// ## Why the grid export and not the image one
///
/// Measured on 2026-09-09, on a desktop CPU with four threads:
///
/// | Export | Output | Time | Peak memory |
/// |---|---|---|---|
/// | PaddlePaddle, image | rectified image at input size | 487 ms at 6.8 MP | **477 MB** |
/// | This one, grid | 45x31 coordinate grid | **173 ms** | **127 MB** |
///
/// The image export can only give a page as large as the tensor it was fed, so
/// a full-resolution scan needs a full-resolution tensor — which on a mid-range
/// phone is an out-of-memory kill rather than a slow operation. The grid export
/// runs at a fixed 720x496 whatever the page, and the resolution of the result
/// is decided afterwards, in Dart, by code that is unit-tested.
///
/// UNVERIFIED: no line of the inference in this file has ever run. The
/// measurements above come from the same models under Python; the Dart binding
/// has not been executed on any device. See `UNVERIFIED.md`.
class UvdocStage implements RestoreStage {
  UvdocStage({required this.modelFile});

  /// The `.onnx` file, with its `.data` sidecar beside it under the exact name
  /// the manifest gives.
  ///
  /// A path rather than a [ModelStore] on purpose: this stage runs inside an
  /// isolate, and a path crosses that boundary while a store full of HTTP
  /// machinery does not.
  final File modelFile;

  /// The input size the export was traced with. Not a tunable: the graph has
  /// these baked in, and anything else is a shape error.
  static const int inputWidth = 496;
  static const int inputHeight = 720;

  OrtSession? _session;

  @override
  String get id => 'uvdoc';

  @override
  Future<StageSkipReason?> unavailableReason() async {
    if (!modelFile.existsSync()) return StageSkipReason.modelNotInstalled;
    return null;
  }

  @override
  Future<ImageBuffer> apply(ImageBuffer input) async {
    final session = _session ??= _open();

    final tensor = OrtValueTensor.createTensorWithDataList(
      _toModelInput(input),
      <int>[1, 3, inputHeight, inputWidth],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = session.run(runOptions, <String, OrtValue>{'image': tensor});
      final grid = _toGrid(outputs.first);
      return remapThroughGrid(input, grid);
    } finally {
      tensor.release();
      runOptions.release();
      outputs?.forEach((value) => value?.release());
    }
  }

  OrtSession _open() {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      // Four threads is a phone's big cluster. Letting it use every core makes
      // the whole device stutter for no gain on a graph this shape.
      ..setIntraOpNumThreads(4)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    return OrtSession.fromFile(modelFile, options);
  }

  /// Releases the inference session.
  ///
  /// Worth calling: the session holds the weights, and 30 MB resident for a
  /// stage the user may not use again is 30 MB the system will eventually take
  /// back by killing something.
  void dispose() {
    _session?.release();
    _session = null;
  }

  /// Resizes to the model's fixed input and lays it out as NCHW floats in
  /// `[0, 1]`, which is what this export was traced expecting.
  ///
  /// Channel-planar, not interleaved. Feeding interleaved data produces no
  /// error at all — just a grid computed from a picture that looks like noise.
  static Float32List _toModelInput(ImageBuffer image) {
    // An identity grid is a bilinear resize, so this reuses the resampler that
    // is already covered by tests instead of adding a second one.
    final resized = remapThroughGrid(
      image,
      SamplingGrid.identity(),
      outputWidth: inputWidth,
      outputHeight: inputHeight,
    );

    final pixels = inputWidth * inputHeight;
    final out = Float32List(pixels * 3);
    final gray = resized.isGray;
    for (var i = 0; i < pixels; i++) {
      if (gray) {
        final value = resized.data[i] / 255.0;
        out[i] = value;
        out[pixels + i] = value;
        out[pixels * 2 + i] = value;
      } else {
        out[i] = resized.data[i * 3] / 255.0;
        out[pixels + i] = resized.data[i * 3 + 1] / 255.0;
        out[pixels * 2 + i] = resized.data[i * 3 + 2] / 255.0;
      }
    }
    return out;
  }

  /// Reads the `[1, 2, gh, gw]` output into a [SamplingGrid].
  ///
  /// The shape is read from the value rather than assumed. A different export
  /// of the same network returns an image instead of a grid, and the difference
  /// is invisible until the page comes out as mush — so this refuses anything
  /// that is not two channels, by name.
  static SamplingGrid _toGrid(OrtValue? value) {
    final raw = value?.value;
    if (raw is! List) {
      throw StateError('UVDoc returned ${raw.runtimeType}, expected a tensor.');
    }
    final batch = raw.first;
    if (batch is! List || batch.length != 2) {
      throw StateError(
        'UVDoc returned ${batch is List ? batch.length : "?"} channels, '
        'expected 2. An export that returns 3 is the image variant, which this '
        'stage cannot use — see the class documentation.',
      );
    }
    final rows = batch.first as List;
    final height = rows.length;
    final width = (rows.first as List).length;

    final flat = Float32List(width * height * 2);
    for (var c = 0; c < 2; c++) {
      final plane = batch[c] as List;
      for (var y = 0; y < height; y++) {
        final row = plane[y] as List;
        for (var x = 0; x < width; x++) {
          flat[c * width * height + y * width + x] = (row[x] as num).toDouble();
        }
      }
    }
    return SamplingGrid.fromPlanar(flat, width: width, height: height);
  }
}

/// Whether an inference session can be opened at all on this platform.
///
/// The plan's biggest declared risk is that ONNX Runtime through Dart FFI does
/// not work on iOS. This is the one-line check that would settle it, and it has
/// not been run on any device.
Future<bool> onnxRuntimeAvailable() async {
  try {
    OrtEnv.instance.init();
    return true;
  } on Object {
    return false;
  } finally {
    if (Platform.isAndroid || Platform.isIOS) {
      // Leave the environment initialised; tearing it down per check costs
      // more than it saves.
    }
  }
}
