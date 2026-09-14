// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'image_buffer.dart';

/// What the restored page should look like.
///
/// The three choices every scanner offers, and they are not only cosmetic:
/// dropping the chroma makes the page encode about three times faster and land
/// two to three times smaller, which for a document is usually the right trade
/// and occasionally the wrong one.
enum PageFilter {
  /// Keep the colours. A receipt with a red stamp, a form with a signature in
  /// blue ink, a page with a photograph on it.
  colour,

  /// Grayscale. The right default for text on paper.
  grayscale,

  /// Grayscale with a hard contrast curve — the classic "black and white"
  /// scan. Text is crisp and the paper is white; anything with a photograph or
  /// a faint pencil note on it is destroyed, which is why it is a choice and
  /// not a default.
  blackAndWhite,
}

/// The classical restoration pipeline: estimate the paper, divide it out, then
/// equalise what is left.
///
/// This runs first and it runs everywhere. It needs no model, no download and
/// no native library; and it is the baseline every neural stage has to beat to
/// justify its 30 MB. Milestone M2 is exactly this, measured over the
/// fifty-document set.
///
/// ## Why it is fast
///
/// The first version of this class analysed the full-resolution image and took
/// **56 seconds on a 12 MP photograph**, which is what a phone camera actually
/// produces. The fix is not a faster loop, it is noticing what the analysis is
/// for: the paper-colour field and the equalisation maps are *low frequency by
/// construction* — the background is deliberately smoothed with a radius of
/// several percent of the image, and the histogram maps describe a coarse grid
/// of tiles. Neither carries any detail worth computing at full resolution.
///
/// So everything is measured on an image scaled down to [analysisWidth], and
/// only the correction is applied at full size, in a single fused pass with
/// integer arithmetic and no per-pixel division. Cost becomes linear in pixels
/// with a small constant, instead of growing with the blur radius — and the
/// radius grew with the image, which is why the old version got quadratically
/// worse rather than merely slow.
class ClassicalRestore {
  const ClassicalRestore({
    this.filter = PageFilter.colour,
    this.backgroundRadius = 0.06,
    this.claheTiles = 8,
    this.claheClipLimit = 3.0,
    this.analysisWidth = 512,
  }) : assert(analysisWidth >= 64, 'too small to estimate anything from');

  /// What the page should end up looking like.
  final PageFilter filter;

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

  /// Longest side of the image the analysis runs on.
  ///
  /// The calibration knob. Raising it makes the paper estimate follow finer
  /// structure at a cost that grows quadratically; lowering it makes
  /// restoration cheaper on a slow device. 512 is enough for the background of
  /// an A4 page photographed by a phone, and the benchmark in
  /// `tool/bench_restore.dart` is how to argue for a different number.
  final int analysisWidth;

  /// Runs the whole pipeline.
  ImageBuffer call(ImageBuffer image) {
    final luma = image.toLuma();
    final analysis = _Analysis.of(luma, image.width, image.height, this);
    return _apply(image, luma, analysis);
  }

  /// The contrast curve for [PageFilter.blackAndWhite], as a 256-entry table.
  ///
  /// A curve rather than a threshold. A hard threshold looks decisive on a
  /// screenshot and eats the anti-aliased edges of every letter, which is
  /// exactly the detail OCR uses; this keeps the transition a few levels wide.
  ///
  /// It costs nothing at run time because it is composed into the equalisation
  /// tables, which the pipeline was going to consult anyway.
  static Uint8List contrastCurve({int low = 96, int high = 176}) {
    final curve = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      if (i <= low) {
        curve[i] = 0;
      } else if (i >= high) {
        curve[i] = 255;
      } else {
        // Smoothstep, so the edge of a glyph keeps a couple of grey levels.
        final t = (i - low) / (high - low);
        curve[i] = (255 * t * t * (3 - 2 * t)).round().clamp(0, 255);
      }
    }
    return curve;
  }

  /// Estimates the colour of the paper at every pixel.
  ///
  /// A plain blur is not enough: where text is dense it drags the estimate down
  /// and the letters come back grey. Taking a local maximum first — the
  /// brightest thing nearby is the paper, since ink is dark — and only then
  /// smoothing gives an estimate that survives a dense paragraph.
  ///
  /// Exposed at full resolution for testing and for callers who want the field
  /// itself. The pipeline calls it on a downscaled image; see the class docs.
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

  /// Contrast-limited adaptive histogram equalisation, full resolution.
  ///
  /// Kept as a standalone operation because it is meaningful on its own and
  /// because the tests pin its behaviour. The pipeline does not call it: it
  /// builds the same tile maps from the analysis image and applies them inside
  /// the fused pass.
  static Uint8List clahe(
    Uint8List luma,
    int width,
    int height, {
    int tiles = 8,
    double clipLimit = 3.0,
  }) {
    final grid = _TileMaps.build(luma, width, height, tiles, clipLimit, null);
    final out = Uint8List(luma.length);
    final columns = grid.columnWeights(width);
    for (var y = 0; y < height; y++) {
      final row = grid.rowWeight(y, height);
      for (var x = 0; x < width; x++) {
        out[y * width + x] = grid.lookup(
          luma[y * width + x],
          columns,
          x,
          row,
        );
      }
    }
    return out;
  }

  /// The one full-resolution pass: divide by the paper, equalise, and — for a
  /// colour scan — carry the correction back into the three channels.
  ///
  /// Everything here is integer arithmetic on lookup tables prepared by
  /// [_Analysis]. There is no division and no floating point in the inner loop,
  /// because at twelve million pixels the inner loop is the whole cost.
  ImageBuffer _apply(ImageBuffer image, Uint8List luma, _Analysis analysis) {
    final width = image.width;
    final height = image.height;
    // Colour is only carried through when the input has it and the caller
    // asked to keep it.
    final keepColour = !image.isGray && filter == PageFilter.colour;
    final source = image.data;
    final out = Uint8List(keepColour ? source.length : width * height);

    final columns = analysis.grid.columnWeights(width);
    final bgColumns = analysis.backgroundColumns(width);

    for (var y = 0; y < height; y++) {
      final rowWeight = analysis.grid.rowWeight(y, height);
      final bgRow = analysis.backgroundRow(y, height);
      final rowStart = y * width;

      for (var x = 0; x < width; x++) {
        final index = rowStart + x;

        // 1. Paper colour here, bilinear from the analysis grid, already
        //    stored as the reciprocal so this is a multiply and a shift.
        final scale = analysis.scaleAt(bgColumns, x, bgRow);
        var flattened = (luma[index] * scale) >> 8;
        if (flattened > 255) flattened = 255;

        // 2. Adaptive equalisation, bilinear between the four nearest tiles.
        final corrected =
            analysis.grid.lookup(flattened, columns, x, rowWeight);

        if (!keepColour) {
          out[index] = corrected;
        } else {
          // 3. Scale the channels by the same ratio the luma moved, which is
          //    what keeps a red stamp red instead of grey.
          final before = luma[index];
          final base = index * 3;
          if (before == 0) {
            out[base] = corrected;
            out[base + 1] = corrected;
            out[base + 2] = corrected;
          } else {
            final ratio = (corrected << 8) ~/ before;
            for (var c = 0; c < 3; c++) {
              final value = (source[base + c] * ratio) >> 8;
              out[base + c] = value > 255 ? 255 : value;
            }
          }
        }
      }
    }
    return ImageBuffer(
      width: width,
      height: height,
      channels: keepColour ? 3 : 1,
      data: out,
    );
  }

  /// Box-average downscale of a single-channel image to at most [target] on the
  /// longer side.
  ///
  /// Averaging rather than sampling: a sampled downscale of a page of text is
  /// mostly ink or mostly paper depending on where the grid lands, and the
  /// paper estimate would flicker with it.
  static ({Uint8List data, int width, int height}) downscale(
    Uint8List luma,
    int width,
    int height,
    int target,
  ) {
    final longest = math.max(width, height);
    if (longest <= target) {
      return (data: luma, width: width, height: height);
    }
    final step = (longest + target - 1) ~/ target;
    final outWidth = math.max(1, width ~/ step);
    final outHeight = math.max(1, height ~/ step);
    final out = Uint8List(outWidth * outHeight);

    for (var y = 0; y < outHeight; y++) {
      final fromY = y * step;
      final toY = math.min(height, fromY + step);
      for (var x = 0; x < outWidth; x++) {
        final fromX = x * step;
        final toX = math.min(width, fromX + step);
        var total = 0;
        var count = 0;
        for (var sy = fromY; sy < toY; sy++) {
          final row = sy * width;
          for (var sx = fromX; sx < toX; sx++) {
            total += luma[row + sx];
            count++;
          }
        }
        out[y * outWidth + x] = count == 0 ? 0 : total ~/ count;
      }
    }
    return (data: out, width: outWidth, height: outHeight);
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

  /// Separable local maximum.
  ///
  /// TODO: naive, so O(pixels x radius). That is fine because the pipeline
  /// only ever runs it on the analysis image, where the radius is a couple of
  /// dozen pixels. Calling it directly on a 12 MP photograph is what made the
  /// first version of this file take a minute; if you ever need that, the
  /// replacement is van Herk / Gil-Werman, which is O(pixels) whatever the
  /// radius.
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

/// Everything measured on the downscaled image, ready to be applied at full
/// resolution without touching a float.
class _Analysis {
  _Analysis({
    required this.scale,
    required this.width,
    required this.height,
    required this.grid,
  });

  /// `255 * 256 / paper` at each analysis pixel: the reciprocal, precomputed,
  /// so the full-resolution pass multiplies and shifts instead of dividing.
  final Int32List scale;
  final int width;
  final int height;
  final _TileMaps grid;

  static _Analysis of(
    Uint8List luma,
    int width,
    int height,
    ClassicalRestore options,
  ) {
    final small = ClassicalRestore.downscale(
      luma,
      width,
      height,
      options.analysisWidth,
    );
    final radius =
        (math.max(small.width, small.height) * options.backgroundRadius)
            .round();
    final background = ClassicalRestore.estimateBackground(
      small.data,
      small.width,
      small.height,
      radius: radius,
    );

    final scale = Int32List(background.length);
    for (var i = 0; i < background.length; i++) {
      final paper = background[i];
      scale[i] = paper == 0 ? 255 * 256 : (255 * 256) ~/ paper;
    }

    // The equalisation maps are built from the flattened analysis image, so
    // they describe the histogram the full-resolution pass will actually see.
    final flattened =
        ClassicalRestore.divideByBackground(small.data, background);
    return _Analysis(
      scale: scale,
      width: small.width,
      height: small.height,
      grid: _TileMaps.build(
        flattened,
        small.width,
        small.height,
        options.claheTiles,
        options.claheClipLimit,
        options.filter == PageFilter.blackAndWhite
            ? ClassicalRestore.contrastCurve()
            : null,
      ),
    );
  }

  /// Per-column indices and weights for sampling the analysis grid, computed
  /// once per image rather than once per pixel.
  Int32List backgroundColumns(int fullWidth) => _bilinearAxis(fullWidth, width);

  ({int low, int high, int weight}) backgroundRow(int y, int fullHeight) {
    final position = ((y * 2 + 1) * height * 128) ~/ fullHeight - 128;
    final low = position < 0 ? 0 : position >> 8;
    final high = math.min(height - 1, low + 1);
    return (
      low: low,
      high: high,
      weight: position < 0 ? 0 : position - (low << 8),
    );
  }

  int scaleAt(
    Int32List columns,
    int x,
    ({int low, int high, int weight}) row,
  ) {
    final lowRow = row.low * width;
    final highRow = row.high * width;
    final index = x * 3;
    final left = columns[index];
    final right = columns[index + 1];
    final weight = columns[index + 2];

    final inverse = 256 - weight;
    final top =
        (scale[lowRow + left] * inverse + scale[lowRow + right] * weight) >> 8;
    final bottom =
        (scale[highRow + left] * inverse + scale[highRow + right] * weight) >>
            8;
    final rowInverse = 256 - row.weight;
    return (top * rowInverse + bottom * row.weight) >> 8;
  }

  /// Triples of `(low, high, weight)` mapping a full-resolution axis onto an
  /// analysis axis, with 8-bit fixed-point weights.
  static Int32List _bilinearAxis(int fullLength, int shortLength) {
    final out = Int32List(fullLength * 3);
    for (var i = 0; i < fullLength; i++) {
      final position = ((i * 2 + 1) * shortLength * 128) ~/ fullLength - 128;
      final low = position < 0 ? 0 : position >> 8;
      final high = math.min(shortLength - 1, low + 1);
      out[i * 3] = low;
      out[i * 3 + 1] = high;
      out[i * 3 + 2] = position < 0 ? 0 : position - (low << 8);
    }
    return out;
  }
}

/// The grid of contrast-limited histogram maps, and the bilinear lookup that
/// stops the tile boundaries from showing up in the output.
class _TileMaps {
  _TileMaps({
    required this.maps,
    required this.tilesX,
    required this.tilesY,
  });

  final List<Uint8List> maps;
  final int tilesX;
  final int tilesY;

  static _TileMaps build(
    Uint8List luma,
    int width,
    int height,
    int tiles,
    double clipLimit,
    Uint8List? curve,
  ) {
    final tilesX = math.max(1, math.min(tiles, width ~/ 8));
    final tilesY = math.max(1, math.min(tiles, height ~/ 8));
    final tileWidth = width / tilesX;
    final tileHeight = height / tilesY;

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
        final equalised = (cumulative * 255 / pixels).round().clamp(0, 255);
        // Composing the filter curve here makes it free: the pipeline already
        // consults this table once per pixel.
        map[i] = curve == null ? equalised : curve[equalised];
      }
      return map;
    });

    return _TileMaps(maps: maps, tilesX: tilesX, tilesY: tilesY);
  }

  Int32List columnWeights(int width) => _Analysis._bilinearAxis(width, tilesX);

  ({int low, int high, int weight}) rowWeight(int y, int height) {
    final position = ((y * 2 + 1) * tilesY * 128) ~/ height - 128;
    final low = position < 0 ? 0 : position >> 8;
    final high = math.min(tilesY - 1, low + 1);
    return (
      low: low,
      high: high,
      weight: position < 0 ? 0 : position - (low << 8),
    );
  }

  int lookup(
    int value,
    Int32List columns,
    int x,
    ({int low, int high, int weight}) row,
  ) {
    final index = x * 3;
    final left = columns[index];
    final right = columns[index + 1];
    final weight = columns[index + 2];

    final topLeft = maps[row.low * tilesX + left][value];
    final topRight = maps[row.low * tilesX + right][value];
    final bottomLeft = maps[row.high * tilesX + left][value];
    final bottomRight = maps[row.high * tilesX + right][value];

    final inverse = 256 - weight;
    final top = (topLeft * inverse + topRight * weight) >> 8;
    final bottom = (bottomLeft * inverse + bottomRight * weight) >> 8;
    final result =
        (top * (256 - row.weight) + bottom * row.weight) >> 8;
    return result < 0 ? 0 : (result > 255 ? 255 : result);
  }
}
