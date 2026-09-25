// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// UNVERIFIED: the framing numbers below ([padFraction] and [toGrid]) were
/// measured on *synthetic* cylindrical pages, through this file's grid
/// `.onnx` but under Python — the timing table above is a separate
/// measurement, of a different `.onnx` export. No real book photograph has
/// ever been measured against a ground truth, and the device runs that did
/// happen record no per-stage outcome, so nothing yet distinguishes this
/// stage running from it being skipped. See `UNVERIFIED.md`, rows U-34 and
/// U-43.
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

  /// Background left around the page inside the model tensor, per side.
  ///
  /// UVDoc has rarely seen a page that touches the edge of its input. The
  /// authors' own data loader (`crop_image_tight` in `data_utils.py`) crops to
  /// the document's bounding box, keeping up to `s = 20` pixels of real
  /// background — less if the photo has less — then randomly trims that down
  /// to roughly 4-20 px per side before resizing, so training pages almost
  /// always float inside the frame. Byrsa rectifies at the quad during
  /// capture, so without this the page arrives edge to edge, which is framing
  /// the network was never trained on. The error it produces is not spread
  /// around: it collects at the four corners, which is exactly what the page
  /// looks like when it comes back twisted.
  ///
  /// Source pixels of error against a ground-truth grid, six synthetic curled
  /// pages at 2250x3000, measured 2026-09-19:
  ///
  /// | Model input | mean | border | corners |
  /// |---|---|---|---|
  /// | ~1.5% real background per side, the framing it was trained on | 20.1 | 18.9 | 19.7 |
  /// | the page edge to edge — before this | 101.6 | 153.6 | **201.0** |
  /// | the page padded here to 3% | 30.9 | 38.6 | **25.1** |
  ///
  /// Not a tuned constant, and it should not be read as one: every measured
  /// pad from 2% to 8% (2, 3, 4, 6, 8%) lands between 21 and 31 px at the
  /// corners, and the colour of the border does not matter either (60, 128 and
  /// 200 agree to within a pixel). 3% sits inside that plateau — it is not its
  /// best point, 2% scored 21.5 at the corners. 12% is where it starts to
  /// cost: 39.3.
  ///
  /// Padding more is not better either. Widening the crop until the page fills
  /// only 67% of the frame (a margin of 25% of the page width on each side)
  /// costs 119 to 152 px at the corners. That is one measurement of a separate
  /// scene, one page at 1500x2000 over three curl radii, and not the six pages
  /// above: too much context is as bad as none. UVDoc wants a tight crop with
  /// a thin border, which is what `crop_image_tight` produces.
  static const double padFraction = 0.03;

  static int get _padX => (inputWidth * padFraction).round();
  static int get _padY => (inputHeight * padFraction).round();

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
      toModelInput(input),
      <int>[1, 3, inputHeight, inputWidth],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = session.run(runOptions, <String, OrtValue>{'image': tensor});
      final grid = toGrid(outputs.first?.value);
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

  /// Resizes the page into the centre of the model's fixed input, leaving a
  /// [padFraction] border, and lays the whole tensor out as NCHW floats in
  /// `[0, 1]`, which is what this export was traced expecting.
  ///
  /// The border is the background the quad crop took away. Flat grey and not
  /// the desk it actually came from: measured with the crop widened so the
  /// page lands on the same tensor pixels with the real desk filling the
  /// border instead, the corners come out about the same (24 vs 25 px) but
  /// the real background does better along the border (26 vs 39 px) — the
  /// quad crop has already discarded it by the time this stage runs, though.
  /// See [padFraction] for why the network needs something there at all.
  ///
  /// Channel-planar, not interleaved. Feeding interleaved data produces no
  /// error at all — just a grid computed from a picture that looks like noise.
  @visibleForTesting
  static Float32List toModelInput(ImageBuffer image) {
    final pageWidth = inputWidth - _padX * 2;
    final pageHeight = inputHeight - _padY * 2;

    // An identity grid sized to the output is an exact align_corners bilinear
    // resize — a node on every output pixel, so the within-cell weight is
    // always zero — and reuses the resampler already covered by tests instead
    // of adding a second one. A bare `SamplingGrid.identity()` is a 2x2 grid:
    // `_axisWeights` quantises the sample position to one of its 257 fixed-
    // point levels per axis, which on a page this size duplicates most rows
    // and columns instead of resizing them.
    final resized = remapThroughGrid(
      image,
      SamplingGrid.identity(width: pageWidth, height: pageHeight),
      outputWidth: pageWidth,
      outputHeight: pageHeight,
    );

    final pixels = inputWidth * inputHeight;
    // Flat mid-grey everywhere first; the page then overwrites the middle. The
    // border has to be something that is not paper, and a constant is the one
    // choice that cannot be mistaken for more page — a mirrored or replicated
    // edge would extend the text out to the frame, which is the very thing
    // this is here to avoid.
    final out = Float32List(pixels * 3)..fillRange(0, pixels * 3, 0.5);
    final gray = resized.isGray;
    for (var y = 0; y < pageHeight; y++) {
      final rowStart = y * pageWidth;
      final targetStart = (y + _padY) * inputWidth + _padX;
      for (var x = 0; x < pageWidth; x++) {
        final target = targetStart + x;
        if (gray) {
          final value = resized.data[rowStart + x] / 255.0;
          out[target] = value;
          out[pixels + target] = value;
          out[pixels * 2 + target] = value;
        } else {
          final source = (rowStart + x) * 3;
          out[target] = resized.data[source] / 255.0;
          out[pixels + target] = resized.data[source + 1] / 255.0;
          out[pixels * 2 + target] = resized.data[source + 2] / 255.0;
        }
      }
    }
    return out;
  }

  /// Reads the `[1, 2, gh, gw]` output into a [SamplingGrid], expressed in the
  /// page's coordinates rather than the padded tensor's.
  ///
  /// The network answers in the frame it was shown, which is the padded canvas;
  /// [remapThroughGrid] samples the page the caller handed in, which is the
  /// rectangle the padding sits around. Both are centred on the same point, so
  /// the conversion is a single scale per axis. With `align_corners = true`, a
  /// canvas coordinate `g` names canvas pixel `(g + 1) / 2 * (inputWidth - 1)`,
  /// which is page pixel `that - padX`, which as a page coordinate is
  /// `2 * (that - padX) / (pageWidth - 1) - 1`. Expand it and the offsets
  /// cancel, leaving `g / scaleX` with `scaleX` the page's share of the canvas.
  ///
  /// This pushes the outermost values slightly past ±1 — measured after the
  /// fix, the grid spans 100.4% of the width and 100.8% of the height, against
  /// 91.3% and 95.4% before it, which at 2250x3000 was 98 px a side horizontally
  /// and 69 px top and bottom — header and footer among the latter — stretched
  /// off the output and silently lost. Past ±1 is not a bug here:
  /// [remapThroughGrid] clamps to the source edge on purpose.
  ///
  /// The shape is read from the value rather than assumed. A different export
  /// of the same network returns an image instead of a grid, and the difference
  /// is invisible until the page comes out as mush — so this refuses anything
  /// that is not two channels, by name.
  @visibleForTesting
  static SamplingGrid toGrid(Object? raw) {
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

    // Plane 0 is x, plane 1 is y. Swapping them is not an error either, just a
    // page transposed on top of itself: measured 12.1 px of grid error as
    // written against 837.9 px swapped.
    final scaleX = (inputWidth - _padX * 2 - 1) / (inputWidth - 1);
    final scaleY = (inputHeight - _padY * 2 - 1) / (inputHeight - 1);

    final flat = Float32List(width * height * 2);
    for (var c = 0; c < 2; c++) {
      final plane = batch[c] as List;
      final scale = c == 0 ? scaleX : scaleY;
      for (var y = 0; y < height; y++) {
        final row = plane[y] as List;
        for (var x = 0; x < width; x++) {
          flat[c * width * height + y * width + x] =
              (row[x] as num).toDouble() / scale;
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
