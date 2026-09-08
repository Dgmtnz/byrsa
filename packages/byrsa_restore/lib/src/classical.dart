// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'image_buffer.dart';

/// The classical restoration pipeline: estimate the paper, divide it out,
/// then equalise what is left.
///
/// This runs first and it runs everywhere. It needs no model, no download and
/// no native library; it costs a few milliseconds; and it is the baseline every
/// neural stage has to beat to justify its 30 MB. Milestone M2 is exactly this
/// measured over the fifty-document set.
class ClassicalRestore {
  const ClassicalRestore({
    this.backgroundRadius = 0.06,
    this.claheTiles = 8,
    this.claheClipLimit = 3.0,
  });

  /// Radius of the paper-colour estimate, as a fraction of the longer side.
  ///
  /// Too small and the estimate follows the text, washing out letters; too
  /// large and a real shadow survives. Six percent is about two lines of body
  /// text at typical capture distances.
  final double backgroundRadius;

  /// Tiles per axis for the adaptive equalisation.
  final int claheTiles;

  /// Contrast limit. Above about 4 the noise in the paper starts to show.
  final double claheClipLimit;

  /// Runs the whole pipeline.
  ImageBuffer call(ImageBuffer image) {
    final luma = image.toLuma();
    final background = estimateBackground(
      luma,
      image.width,
      image.height,
      radius: (math.max(image.width, image.height) * backgroundRadius).round(),
    );
    final flattened = divideByBackground(luma, background);
    final equalised = clahe(
      flattened,
      image.width,
      image.height,
      tiles: claheTiles,
      clipLimit: claheClipLimit,
    );
    return image.withLuma(equalised);
  }

  /// Estimates the colour of the paper at every pixel.
  ///
  /// A plain blur is not enough: where text is dense it drags the estimate
  /// down and the letters come back grey. Taking a local maximum first — the
  /// brightest thing nearby is the paper, since ink is dark — and only then
  /// smoothing gives an estimate that survives a dense paragraph.
  static Uint8List estimateBackground(
    Uint8List luma,
    int width,
    int height, {
    required int radius,
  }) {
    final r = math.min(math.max(radius, 2), math.max(width, height));
    final dilated = _maxFilter(luma, width, height, r ~/ 2);
    return _boxBlur(dilated, width, height, r);
  }

  /// Divides the image by its own background, which is what removes a shadow.
  static Uint8List divideByBackground(Uint8List luma, Uint8List background) {
    final out = Uint8List(luma.length);
    for (var i = 0; i < luma.length; i++) {
      final paper = background[i];
      out[i] = paper == 0 ? 255 : (luma[i] * 255 / paper).round().clamp(0, 255);
    }
    return out;
  }

  /// Contrast-limited adaptive histogram equalisation.
  ///
  /// Adaptive because a scan is not uniformly lit even after the division, and
  /// contrast-limited because plain adaptive equalisation turns clean paper
  /// into visible noise. Tile mappings are interpolated bilinearly, which is
  /// what stops the tile grid showing up in the output.
  static Uint8List clahe(
    Uint8List luma,
    int width,
    int height, {
    int tiles = 8,
    double clipLimit = 3.0,
  }) {
    final tilesX = math.max(1, math.min(tiles, width ~/ 8));
    final tilesY = math.max(1, math.min(tiles, height ~/ 8));
    final tileWidth = width / tilesX;
    final tileHeight = height / tilesY;

    // One 256-entry lookup table per tile.
    final maps = List<Uint8List>.generate(tilesX * tilesY, (index) {
      final tx = index % tilesX;
      final ty = index ~/ tilesX;
      final x0 = (tx * tileWidth).floor();
      final x1 = ((tx + 1) * tileWidth).ceil().clamp(0, width);
      final y0 = (ty * tileHeight).floor();
      final y1 = ((ty + 1) * tileHeight).ceil().clamp(0, height);

      final histogram = Int32List(256);
      for (var y = y0; y < y1; y++) {
        final row = y * width;
        for (var x = x0; x < x1; x++) {
          histogram[luma[row + x]]++;
        }
      }
      final pixels = (x1 - x0) * (y1 - y0);
      if (pixels == 0) {
        return Uint8List.fromList(List<int>.generate(256, (i) => i));
      }

      // Clip the histogram and spread what was clipped back over every bin,
      // which is the "contrast-limited" half of the name.
      final limit = math.max(1, (clipLimit * pixels / 256).round());
      var excess = 0;
      for (var i = 0; i < 256; i++) {
        if (histogram[i] > limit) {
          excess += histogram[i] - limit;
          histogram[i] = limit;
        }
      }
      final share = excess ~/ 256;
      var remainder = excess - share * 256;
      for (var i = 0; i < 256; i++) {
        histogram[i] += share;
        if (remainder > 0) {
          histogram[i]++;
          remainder--;
        }
      }

      final map = Uint8List(256);
      var cumulative = 0;
      for (var i = 0; i < 256; i++) {
        cumulative += histogram[i];
        map[i] = (cumulative * 255 / pixels).round().clamp(0, 255);
      }
      return map;
    });

    final out = Uint8List(luma.length);
    for (var y = 0; y < height; y++) {
      // Position within the grid of tile centres.
      final fy = (y + 0.5) / tileHeight - 0.5;
      final ty0 = fy.floor().clamp(0, tilesY - 1);
      final ty1 = (ty0 + 1).clamp(0, tilesY - 1);
      final wy = (fy - ty0).clamp(0.0, 1.0);

      for (var x = 0; x < width; x++) {
        final fx = (x + 0.5) / tileWidth - 0.5;
        final tx0 = fx.floor().clamp(0, tilesX - 1);
        final tx1 = (tx0 + 1).clamp(0, tilesX - 1);
        final wx = (fx - tx0).clamp(0.0, 1.0);

        final value = luma[y * width + x];
        final topLeft = maps[ty0 * tilesX + tx0][value].toDouble();
        final topRight = maps[ty0 * tilesX + tx1][value].toDouble();
        final bottomLeft = maps[ty1 * tilesX + tx0][value].toDouble();
        final bottomRight = maps[ty1 * tilesX + tx1][value].toDouble();

        final top = topLeft + (topRight - topLeft) * wx;
        final bottom = bottomLeft + (bottomRight - bottomLeft) * wx;
        out[y * width + x] = (top + (bottom - top) * wy).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Separable box blur via running sums: O(pixels), independent of radius.
  static Uint8List _boxBlur(
      Uint8List source, int width, int height, int radius) {
    final horizontal = Uint8List(source.length);
    final window = radius * 2 + 1;

    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = 0;
      for (var x = -radius; x <= radius; x++) {
        sum += source[row + x.clamp(0, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        horizontal[row + x] = (sum / window).round();
        sum -= source[row + (x - radius).clamp(0, width - 1)];
        sum += source[row + (x + radius + 1).clamp(0, width - 1)];
      }
    }

    final out = Uint8List(source.length);
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var y = -radius; y <= radius; y++) {
        sum += horizontal[y.clamp(0, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        out[y * width + x] = (sum / window).round();
        sum -= horizontal[(y - radius).clamp(0, height - 1) * width + x];
        sum += horizontal[(y + radius + 1).clamp(0, height - 1) * width + x];
      }
    }
    return out;
  }

  /// Separable local maximum. Separable because max is, and a naive square
  /// window is quadratic in the radius, which is exactly the radius we need.
  static Uint8List _maxFilter(
      Uint8List source, int width, int height, int radius) {
    if (radius < 1) return Uint8List.fromList(source);
    final horizontal = Uint8List(source.length);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        var best = 0;
        final from = math.max(0, x - radius);
        final to = math.min(width - 1, x + radius);
        for (var i = from; i <= to; i++) {
          final value = source[row + i];
          if (value > best) best = value;
        }
        horizontal[row + x] = best;
      }
    }
    final out = Uint8List(source.length);
    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        var best = 0;
        final from = math.max(0, y - radius);
        final to = math.min(height - 1, y + radius);
        for (var i = from; i <= to; i++) {
          final value = horizontal[i * width + x];
          if (value > best) best = value;
        }
        out[y * width + x] = best;
      }
    }
    return out;
  }
}
