// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'classical.dart';
import 'dewarp.dart';
import 'image_buffer.dart';
import 'pipeline.dart';

/// Removes a thumb, a finger or anything else holding the page down at the
/// edge of a scan, and fills in the paper behind it.
///
/// ## Why this does not look for skin
///
/// The obvious implementation, and the one the project plan originally
/// proposed, is a skin-colour mask in HSV or YCbCr. It is a bad idea here.
/// Those thresholds come overwhelmingly from light-skinned training data, so a
/// scanner built on them works better for some users than others — an
/// unacceptable property for a feature that either fires or does not, on a
/// photograph of someone's own hand.
///
/// So the test is not "is this skin" but **"is this not paper, and is it
/// holding on to the edge of the frame"**:
///
/// 1. Estimate the paper from a high percentile of the page's brightness.
/// 2. Mark whatever *differs* from the paper, in either direction.
/// 3. Keep only what is connected to the border of the image.
/// 4. Keep only what is *thick* — a finger survives an erosion, a line of text
///    does not.
/// 5. Throw away anything that reaches two opposite edges. A hand comes in
///    from one side of a photograph; it does not cross the whole page.
///
/// Step 2 says "differs", not "is darker", and the difference is the whole
/// point. An earlier version of this class tested for darker-than-paper, and
/// its own test caught the consequence: a thumb photographed in good light
/// reads around 190 against paper at 242 and was missed entirely, while a
/// darker hand was caught every time. That is the same bias as a skin-colour
/// mask wearing different clothes. Distance from the paper, in either
/// direction, has no such preference.
///
/// That is tone-agnostic by construction, and it catches things a skin
/// detector never would: a gloved hand, a pen, a dark table edge, the shadow
/// the holder casts. A stamp in the middle of the page is untouched, because
/// it does not reach the border.
///
/// Rule 5 was not in the first version, and the test that found it is worth
/// keeping in mind. Illumination normalisation used to leave a **halo at a
/// hard shadow edge** — dividing by a background built from a local maximum
/// overestimates on the dark side of a sharp step, and a dark stripe survived
/// where the edge was. That stripe is thick, differs from the paper, and
/// touches the border, so it passed every other test. It also runs the full
/// height of the page, which no hand does.
///
/// The background is now a closing (D-054). Along a straight shadow edge what
/// survives is a few pixels wide, and nothing here takes it for a hand, rule 5
/// or not. Along a diagonal one a thin dark line survives, and after the
/// threshold and the erosion what is left of it touches only one edge of the
/// page, so rule 5 lets it through and the fill erases the text under it.
/// That was measured on the synthetic hand-shadow documents, where no hand is
/// in frame, and it is why the application leaves this stage off by default
/// (D-055).
///
/// ## Where in the pipeline
///
/// After illumination normalisation. On a raw capture the paper estimate is
/// dragged around by the shadow itself, and the detection is then held up only
/// by the safety valve on [maximumAreaFraction] — which is luck, not design.
///
/// ## Why it works at a reduced scale
///
/// The fill is paper: smooth, low-frequency, and carrying no detail worth
/// computing per pixel. So detection and filling happen on a downscaled copy
/// and only the blend touches the full-resolution image — the same argument as
/// the illumination field in D-029 and the dewarping grid in D-037.
class BorderIntrusion {
  const BorderIntrusion({
    this.analysisWidth = 384,
    this.differsFromPaper = 0.12,
    this.minimumThickness = 3,
    this.minimumAreaFraction = 0.004,
    this.maximumAreaFraction = 0.45,
  }) : assert(analysisWidth >= 64, 'too small to find anything in');

  /// Longest side the detection runs on.
  final int analysisWidth;

  /// How far from the paper's brightness a pixel must be to be suspicious, in
  /// either direction, as a fraction of that brightness.
  ///
  /// Generous on purpose. The thickness and border tests do the discriminating;
  /// this only has to avoid discarding an intruding object before they run, and
  /// it must not care whether the object is lighter or darker than the page.
  final double differsFromPaper;

  /// Erosions a region must survive, in analysis pixels.
  ///
  /// This is the whole discriminator between a finger and a line of text, and
  /// it is why the detection does not need to know what skin looks like.
  final int minimumThickness;

  /// Below this share of the page, a region is left alone.
  final double minimumAreaFraction;

  /// Above this share, the detection is assumed to be wrong.
  ///
  /// A mask covering half the page means the paper estimate failed — a very
  /// dark photograph, or a page that is mostly a photograph. Erasing half a
  /// scan is far worse than leaving a thumb in the corner.
  final double maximumAreaFraction;

  /// Finds intruding regions and returns a mask at the analysis scale.
  ///
  /// Exposed so a caller can show the user what would be removed, and so the
  /// tests can check the decision rather than only the pixels.
  ({Uint8List mask, int width, int height, double areaFraction}) detect(
    ImageBuffer image,
  ) {
    final luma = image.toLuma();
    final small = ClassicalRestore.downscale(
      luma,
      image.width,
      image.height,
      analysisWidth,
    );
    final width = small.width;
    final height = small.height;
    final pixels = width * height;

    // 1. The paper: a high percentile rather than the maximum, so one specular
    //    highlight cannot set the reference for the whole page.
    final histogram = Int32List(256);
    for (final value in small.data) {
      histogram[value]++;
    }
    var seen = 0;
    var paper = 255;
    for (var i = 0; i < 256; i++) {
      seen += histogram[i];
      if (seen >= (pixels * 0.80).round()) {
        paper = i;
        break;
      }
    }
    // A floor as well as a fraction, so paper grain on a dim page does not
    // register as an object.
    final tolerance = math.max(24, (paper * differsFromPaper).round());

    // 2. Whatever differs from the paper, lighter or darker.
    final dark = Uint8List(pixels);
    for (var i = 0; i < pixels; i++) {
      dark[i] = (small.data[i] - paper).abs() > tolerance ? 1 : 0;
    }

    // 3. Thick enough to be an object rather than a stroke of ink. Eroding
    //    first and regrowing afterwards keeps the object's real outline while
    //    deleting everything too thin to have survived.
    final thick = _regrow(_erode(dark, width, height, minimumThickness), width,
        height, minimumThickness + 1);

    // 4. Connected to the border. A hand reaches in from outside the page; a
    //    stamp or a photograph in the middle of it does not.
    //
    // 5. And not spanning the page. Done together, because the flood already
    //    knows which edges each region touched.
    final mask = _floodFromBorder(thick, width, height);

    var area = 0;
    for (final value in mask) {
      if (value != 0) area++;
    }
    final fraction = area / pixels;
    if (fraction < minimumAreaFraction || fraction > maximumAreaFraction) {
      return (
        mask: Uint8List(pixels),
        width: width,
        height: height,
        areaFraction: 0,
      );
    }
    return (mask: mask, width: width, height: height, areaFraction: fraction);
  }

  /// Removes what [detect] finds, filling the hole with the surrounding paper.
  ImageBuffer call(ImageBuffer image) {
    final found = detect(image);
    if (found.areaFraction == 0) return image;

    final width = found.width;
    final height = found.height;
    final channels = image.channels;

    // Fill at the analysis scale, by pulling paper inward from the edge of the
    // hole one ring at a time. The result is smooth, which is exactly right
    // for paper and exactly wrong for anything else — hence the border test.
    final smallImage = _downscaleChannels(image, width, height);
    final filled = _fillInward(smallImage, found.mask, width, height, channels);

    // A hard edge on the mask reads as a cut-out. Blurring it turns the seam
    // into a gradient the eye does not catch.
    final feather = _blur(
      Uint8List.fromList(found.mask.map((v) => v != 0 ? 255 : 0).toList()),
      width,
      height,
      math.max(2, minimumThickness),
    );

    final fillFull = remapThroughGrid(
      ImageBuffer(
        width: width,
        height: height,
        channels: channels,
        data: filled,
      ),
      SamplingGrid.identity(),
      outputWidth: image.width,
      outputHeight: image.height,
    );
    final featherFull = remapThroughGrid(
      ImageBuffer.gray(width, height, feather),
      SamplingGrid.identity(),
      outputWidth: image.width,
      outputHeight: image.height,
    );

    final out = Uint8List(image.data.length);
    for (var i = 0; i < image.pixelCount; i++) {
      final weight = featherFull.data[i];
      if (weight == 0) {
        for (var c = 0; c < channels; c++) {
          out[i * channels + c] = image.data[i * channels + c];
        }
        continue;
      }
      for (var c = 0; c < channels; c++) {
        final original = image.data[i * channels + c];
        final replacement = fillFull.data[i * channels + c];
        out[i * channels + c] =
            (original * (256 - weight) + replacement * weight) >> 8;
      }
    }
    return ImageBuffer(
      width: image.width,
      height: image.height,
      channels: channels,
      data: out,
    );
  }

  static Uint8List _downscaleChannels(
      ImageBuffer image, int width, int height) {
    final resized = remapThroughGrid(
      image,
      SamplingGrid.identity(),
      outputWidth: width,
      outputHeight: height,
    );
    return resized.data;
  }

  /// Replaces the masked region with paper pulled inward from its boundary.
  static Uint8List _fillInward(
    Uint8List data,
    Uint8List mask,
    int width,
    int height,
    int channels,
  ) {
    final out = Uint8List.fromList(data);
    final remaining = Uint8List.fromList(mask);
    var left = remaining.where((v) => v != 0).length;

    // One ring per pass. Bounded so a pathological mask cannot spin forever.
    for (var pass = 0; pass < width + height && left > 0; pass++) {
      final filledThisPass = <int>[];
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = y * width + x;
          if (remaining[index] == 0) continue;
          var count = 0;
          final sums = List<int>.filled(channels, 0);
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
              final neighbour = ny * width + nx;
              if (remaining[neighbour] != 0) continue;
              count++;
              for (var c = 0; c < channels; c++) {
                sums[c] += out[neighbour * channels + c];
              }
            }
          }
          if (count == 0) continue;
          for (var c = 0; c < channels; c++) {
            out[index * channels + c] = sums[c] ~/ count;
          }
          filledThisPass.add(index);
        }
      }
      if (filledThisPass.isEmpty) break;
      for (final index in filledThisPass) {
        remaining[index] = 0;
      }
      left -= filledThisPass.length;
    }
    return out;
  }

  static Uint8List _erode(Uint8List mask, int width, int height, int radius) {
    var current = mask;
    for (var step = 0; step < radius; step++) {
      final next = Uint8List(current.length);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = y * width + x;
          if (current[index] == 0) continue;
          var keep = true;
          for (var dy = -1; dy <= 1 && keep; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              // Outside the frame counts as set: a finger runs off the edge of
              // the photograph and must not be eroded away from that side.
              if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
              if (current[ny * width + nx] == 0) {
                keep = false;
                break;
              }
            }
          }
          next[index] = keep ? 1 : 0;
        }
      }
      current = next;
    }
    return current;
  }

  static Uint8List _regrow(Uint8List mask, int width, int height, int radius) {
    var current = mask;
    for (var step = 0; step < radius; step++) {
      final next = Uint8List.fromList(current);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          if (current[y * width + x] == 0) continue;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
              next[ny * width + nx] = 1;
            }
          }
        }
      }
      current = next;
    }
    return current;
  }

  /// Keeps regions of [mask] that touch the border but do not cross the page.
  ///
  /// Each connected region is grown separately so the edges it reaches can be
  /// recorded. A region touching two opposite edges is not a hand — it is a
  /// stripe across the whole image, which is what the halo at a hard shadow
  /// edge used to be (see the class docs).
  static Uint8List _floodFromBorder(Uint8List mask, int width, int height) {
    final out = Uint8List(mask.length);
    final visited = Uint8List(mask.length);

    for (var start = 0; start < mask.length; start++) {
      if (mask[start] == 0 || visited[start] != 0) continue;
      final x0 = start % width;
      final y0 = start ~/ width;
      final onBorder =
          x0 == 0 || y0 == 0 || x0 == width - 1 || y0 == height - 1;
      if (!onBorder) continue;

      final region = <int>[];
      final queue = <int>[start];
      visited[start] = 1;
      var touchesLeft = false;
      var touchesRight = false;
      var touchesTop = false;
      var touchesBottom = false;

      while (queue.isNotEmpty) {
        final index = queue.removeLast();
        region.add(index);
        final x = index % width;
        final y = index ~/ width;
        if (x == 0) touchesLeft = true;
        if (x == width - 1) touchesRight = true;
        if (y == 0) touchesTop = true;
        if (y == height - 1) touchesBottom = true;

        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            final neighbour = ny * width + nx;
            if (mask[neighbour] == 0 || visited[neighbour] != 0) continue;
            visited[neighbour] = 1;
            queue.add(neighbour);
          }
        }
      }

      if ((touchesLeft && touchesRight) || (touchesTop && touchesBottom)) {
        continue;
      }
      for (final index in region) {
        out[index] = 255;
      }
    }
    return out;
  }

  static Uint8List _blur(Uint8List data, int width, int height, int radius) {
    final horizontal = Uint8List(data.length);
    final window = radius * 2 + 1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = 0;
      for (var x = -radius; x <= radius; x++) {
        sum += data[row + x.clamp(0, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        horizontal[row + x] = sum ~/ window;
        sum -= data[row + (x - radius).clamp(0, width - 1)];
        sum += data[row + (x + radius + 1).clamp(0, width - 1)];
      }
    }
    final out = Uint8List(data.length);
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var y = -radius; y <= radius; y++) {
        sum += horizontal[y.clamp(0, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        out[y * width + x] = sum ~/ window;
        sum -= horizontal[(y - radius).clamp(0, height - 1) * width + x];
        sum += horizontal[(y + radius + 1).clamp(0, height - 1) * width + x];
      }
    }
    return out;
  }
}

/// [BorderIntrusion] as a pipeline stage.
class IntrusionStage implements RestoreStage {
  const IntrusionStage([this.remover = const BorderIntrusion()]);

  final BorderIntrusion remover;

  @override
  String get id => 'intrusion';

  @override
  Future<StageSkipReason?> unavailableReason() async => null;

  @override
  Future<ImageBuffer> apply(ImageBuffer input) async => remover(input);
}
