// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'image_buffer.dart';

/// A coordinate field that says, for each point of the output, where to read
/// from in the input.
///
/// This is what a dewarping network should produce, and the reason matters more
/// than it looks. A network that outputs a *rectified image* can only give you
/// a page as large as the tensor you fed it, so a full-resolution scan means a
/// full-resolution tensor — measured at 477 MB of peak memory for a 6.8 MP
/// page, which is an out-of-memory kill on a mid-range phone. A network that
/// outputs a grid runs at its own small fixed size and the grid is then
/// stretched over an image of any resolution.
///
/// Coordinates follow the `grid_sample` convention: `[-1, -1]` is the top-left
/// corner of the source and `[1, 1]` the bottom-right, independent of pixels.
class SamplingGrid {
  SamplingGrid({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
  }) {
    if (x.length != width * height || y.length != width * height) {
      throw ArgumentError(
        'A ${width}x$height grid needs ${width * height} values per axis.',
      );
    }
  }

  /// Reads a network output shaped `[1, 2, height, width]`.
  ///
  /// Channel-planar, which is what NCHW means and what every ONNX export of
  /// this shape produces: all the x values, then all the y values.
  factory SamplingGrid.fromPlanar(
    Float32List output, {
    required int width,
    required int height,
  }) {
    final count = width * height;
    if (output.length < count * 2) {
      throw ArgumentError(
        'Expected ${count * 2} values for a ${width}x$height grid, '
        'got ${output.length}.',
      );
    }
    return SamplingGrid(
      width: width,
      height: height,
      x: Float32List.sublistView(output, 0, count),
      y: Float32List.sublistView(output, count, count * 2),
    );
  }

  /// A grid that changes nothing. Useful as a fallback and as a test oracle.
  factory SamplingGrid.identity({int width = 2, int height = 2}) {
    final x = Float32List(width * height);
    final y = Float32List(width * height);
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final index = row * width + column;
        x[index] = width == 1 ? 0 : column / (width - 1) * 2 - 1;
        y[index] = height == 1 ? 0 : row / (height - 1) * 2 - 1;
      }
    }
    return SamplingGrid(width: width, height: height, x: x, y: y);
  }

  final int width;
  final int height;

  /// Horizontal source coordinate, in `[-1, 1]`, row-major.
  final Float32List x;

  /// Vertical source coordinate, in `[-1, 1]`, row-major.
  final Float32List y;
}

/// Remaps [source] through [grid], producing an image of any size.
///
/// Two bilinear interpolations per pixel: one to read the coordinate field,
/// which is far coarser than the image and has to be smooth, and one to read
/// the source at the resulting fractional position. Nearest-neighbour on either
/// is visible immediately — a stepped edge on every line of text.
///
/// Coordinates outside the source are clamped to its edge rather than left
/// black. A dewarp that pushes slightly past the paper is normal; a black wedge
/// down the side of the page is not.
ImageBuffer remapThroughGrid(
  ImageBuffer source,
  SamplingGrid grid, {
  int? outputWidth,
  int? outputHeight,
}) {
  final width = outputWidth ?? source.width;
  final height = outputHeight ?? source.height;
  if (width < 1 || height < 1) {
    throw ArgumentError('Output must be at least one pixel.');
  }

  final channels = source.channels;
  final out = Uint8List(width * height * channels);

  // Per-axis grid lookup, computed once instead of once per pixel.
  final columns = _axisWeights(width, grid.width);
  final rows = _axisWeights(height, grid.height);

  final maxX = source.width - 1;
  final maxY = source.height - 1;

  for (var oy = 0; oy < height; oy++) {
    final rowLow = rows[oy * 3] * grid.width;
    final rowHigh = rows[oy * 3 + 1] * grid.width;
    final rowWeight = rows[oy * 3 + 2] / 256.0;

    for (var ox = 0; ox < width; ox++) {
      final columnLow = columns[ox * 3];
      final columnHigh = columns[ox * 3 + 1];
      final columnWeight = columns[ox * 3 + 2] / 256.0;

      // 1. Where does this output pixel read from?
      final gx = _bilinear(
        grid.x[rowLow + columnLow],
        grid.x[rowLow + columnHigh],
        grid.x[rowHigh + columnLow],
        grid.x[rowHigh + columnHigh],
        columnWeight,
        rowWeight,
      );
      final gy = _bilinear(
        grid.y[rowLow + columnLow],
        grid.y[rowLow + columnHigh],
        grid.y[rowHigh + columnLow],
        grid.y[rowHigh + columnHigh],
        columnWeight,
        rowWeight,
      );

      // 2. Read the source there. `(g + 1) / 2 * (size - 1)` is the
      //    `align_corners = true` convention: -1 and 1 name the centres of the
      //    first and last pixels, not the outer edges of the image.
      final sx = ((gx + 1) / 2 * maxX).clamp(0.0, maxX.toDouble());
      final sy = ((gy + 1) / 2 * maxY).clamp(0.0, maxY.toDouble());
      final x0 = sx.floor();
      final y0 = sy.floor();
      final x1 = math.min(x0 + 1, maxX);
      final y1 = math.min(y0 + 1, maxY);
      final fx = sx - x0;
      final fy = sy - y0;

      final base00 = (y0 * source.width + x0) * channels;
      final base01 = (y0 * source.width + x1) * channels;
      final base10 = (y1 * source.width + x0) * channels;
      final base11 = (y1 * source.width + x1) * channels;
      final target = (oy * width + ox) * channels;

      for (var c = 0; c < channels; c++) {
        final value = _bilinear(
          source.data[base00 + c].toDouble(),
          source.data[base01 + c].toDouble(),
          source.data[base10 + c].toDouble(),
          source.data[base11 + c].toDouble(),
          fx,
          fy,
        );
        out[target + c] = value.round().clamp(0, 255);
      }
    }
  }

  return ImageBuffer(
    width: width,
    height: height,
    channels: channels,
    data: out,
  );
}

double _bilinear(
  double topLeft,
  double topRight,
  double bottomLeft,
  double bottomRight,
  double fx,
  double fy,
) {
  final top = topLeft + (topRight - topLeft) * fx;
  final bottom = bottomLeft + (bottomRight - bottomLeft) * fx;
  return top + (bottom - top) * fy;
}

/// Triples of `(low, high, weight)` mapping an output axis onto a grid axis,
/// with 8-bit fixed-point weights.
///
/// `align_corners = true`, matching UVDoc's own `bilinear_unwarping`, which
/// upsamples the grid with `F.interpolate(..., align_corners=True)` and samples
/// with `F.grid_sample(..., align_corners=True)`. Both halves of the convention
/// have to agree, and getting one wrong shifts the whole page by half a grid
/// cell — which on a 31-wide grid over a 3000-pixel page is 48 pixels.
///
/// Note this differs from the ONNX export's own `example.py`, which upsamples
/// the grid with `cv2.resize`. That is `align_corners = false`, and it flattens
/// the outer half-cell of the grid at every edge. The original authors' code is
/// the reference here.
Int32List _axisWeights(int outputLength, int gridLength) {
  final out = Int32List(outputLength * 3);
  for (var i = 0; i < outputLength; i++) {
    final position =
        outputLength == 1 ? 0.0 : i / (outputLength - 1) * (gridLength - 1);
    final low = position.floor().clamp(0, gridLength - 1);
    final high = math.min(low + 1, gridLength - 1);
    out[i * 3] = low;
    out[i * 3 + 1] = high;
    out[i * 3 + 2] = ((position - low) * 256).round().clamp(0, 256);
  }
  return out;
}
