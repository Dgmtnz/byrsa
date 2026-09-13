// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:test/test.dart';

const int _width = 240;
const int _height = 320;

/// A synthetic page: white paper, dark text lines, and a shadow falling across
/// it from the left, which is what a hand or a phone body actually does.
ImageBuffer syntheticPage({double shadowStrength = 0.55}) {
  final data = Uint8List(_width * _height);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      // Text: dark bars every 16 rows, with margins.
      final onLine = (y % 16) < 6 && y > 24 && y < _height - 24;
      final inColumn = x > 20 && x < _width - 20;
      final paper = onLine && inColumn ? 40 : 245;

      // Multiplicative shadow, strongest at the left edge.
      final shade = shadowStrength + (1 - shadowStrength) * (x / _width);
      data[y * _width + x] = (paper * shade).round().clamp(0, 255);
    }
  }
  return ImageBuffer.gray(_width, _height, data);
}

/// Standard deviation of the paper — the parts with no text on them.
double paperSpread(ImageBuffer image) {
  final values = <int>[];
  for (var y = 0; y < _height; y++) {
    if ((y % 16) < 8) continue; // skip text rows and their neighbourhood
    for (var x = 30; x < _width - 30; x++) {
      values.add(image.data[y * _width + x]);
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
          values.length;
  return math.sqrt(variance);
}

/// Difference between paper and ink, averaged over the darkest and lightest
/// bands. Higher is a more readable page.
double inkContrast(ImageBuffer image) {
  var ink = 0.0;
  var inkCount = 0;
  var paper = 0.0;
  var paperCount = 0;
  for (var y = 32; y < _height - 32; y++) {
    final onLine = (y % 16) < 6;
    for (var x = 30; x < _width - 30; x++) {
      final value = image.data[y * _width + x];
      if (onLine) {
        ink += value;
        inkCount++;
      } else if ((y % 16) >= 8) {
        paper += value;
        paperCount++;
      }
    }
  }
  return (paper / paperCount) - (ink / inkCount);
}

void main() {
  group('classical restoration', () {
    test('flattens a shadow that falls across the page', () {
      final before = syntheticPage();
      final after = const ClassicalRestore()(before);

      // The shadow is the dominant source of variation on blank paper.
      expect(paperSpread(after), lessThan(paperSpread(before) / 3),
          reason: 'paper should come out near-uniform');
    });

    test('does not pay for that by losing the text', () {
      final before = syntheticPage();
      final after = const ClassicalRestore()(before);
      expect(inkContrast(after), greaterThan(inkContrast(before)));
    });

    test('leaves an evenly lit page alone rather than damaging it', () {
      // The failure mode worth guarding: a pipeline that always "improves"
      // something makes a good scan worse.
      final flat = syntheticPage(shadowStrength: 1);
      final after = const ClassicalRestore()(flat);
      expect(inkContrast(after), greaterThan(inkContrast(flat) * 0.9));
      expect(paperSpread(after), lessThan(12));
    });

    test('keeps colours as colours: a red stamp does not come back grey', () {
      // The invariant that matters for a colour scan. A flat colour field is
      // not a useful test — after dividing out the background, paper is
      // supposed to become paper-white; what must survive is hue on ink.
      final data = Uint8List(_width * _height * 3);
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          final i = (y * _width + x) * 3;
          final red = x > 40 && x < 100 && y > 100 && y < 160;
          final blue = x > 140 && x < 200 && y > 100 && y < 160;
          final shade = 0.55 + 0.45 * (x / _width);
          final (r, g, b) = red
              ? (200, 55, 50)
              : blue
                  ? (50, 60, 200)
                  : (246, 244, 238);
          data[i] = (r * shade).round();
          data[i + 1] = (g * shade).round();
          data[i + 2] = (b * shade).round();
        }
      }
      final restored = const ClassicalRestore()(
        ImageBuffer(width: _width, height: _height, channels: 3, data: data),
      );

      int channel(int x, int y, int c) =>
          restored.data[(y * _width + x) * 3 + c];
      expect(channel(70, 130, 0), greaterThan(channel(70, 130, 1) + 40),
          reason: 'the red block must stay red');
      expect(channel(170, 130, 2), greaterThan(channel(170, 130, 1) + 40),
          reason: 'the blue block must stay blue');
    });

    test('estimates the paper without following the text into the ink', () {
      // The reason for the local maximum before the blur: a dense paragraph
      // must not drag the paper estimate down.
      final page = syntheticPage(shadowStrength: 1);
      final background = ClassicalRestore.estimateBackground(
        page.data,
        _width,
        _height,
        radius: 20,
      );
      final middle = background[(_height ~/ 2) * _width + _width ~/ 2];
      expect(middle, greaterThan(200));
    });
  });

  group('page filters', () {
    ImageBuffer colourPage() {
      final data = Uint8List(_width * _height * 3);
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          final i = (y * _width + x) * 3;
          final text = (y % 16) < 6 && y > 24 && x > 20 && x < _width - 20;
          final stamp = x > 40 && x < 100 && y > 200 && y < 260;
          final shade = 0.6 + 0.4 * (x / _width);
          final (r, g, b) =
              stamp ? (200, 50, 45) : (text ? (40, 40, 40) : (245, 243, 238));
          data[i] = (r * shade).round();
          data[i + 1] = (g * shade).round();
          data[i + 2] = (b * shade).round();
        }
      }
      return ImageBuffer(
          width: _width, height: _height, channels: 3, data: data);
    }

    test('grayscale drops the chroma, which is most of the file', () {
      final restored = const ClassicalRestore(
        filter: PageFilter.grayscale,
      )(colourPage());
      expect(restored.channels, 1);
      expect(restored.data.length, _width * _height);
    });

    test('colour is the only filter that keeps a red stamp red', () {
      final page = colourPage();
      final colour = const ClassicalRestore(filter: PageFilter.colour)(page);
      final gray = const ClassicalRestore(filter: PageFilter.grayscale)(page);

      final index = (230 * _width + 70);
      expect(
          colour.data[index * 3], greaterThan(colour.data[index * 3 + 1] + 40));
      expect(gray.channels, 1, reason: 'grayscale has nowhere to keep it');
    });

    test('black and white pushes paper to white and ink to black', () {
      final restored = const ClassicalRestore(
        filter: PageFilter.blackAndWhite,
      )(syntheticPage());

      var paper = 0;
      var ink = 0;
      for (var y = 40; y < _height - 40; y++) {
        for (var x = 40; x < _width - 40; x++) {
          final v = restored.data[y * _width + x];
          if (v >= 250) paper++;
          if (v <= 5) ink++;
        }
      }
      final total = (_height - 80) * (_width - 80);
      expect((paper + ink) / total, greaterThan(0.9),
          reason: 'almost every pixel should be at one end or the other');
      expect(ink, greaterThan(total ~/ 50), reason: 'the text must survive');
    });

    test('the contrast curve keeps an edge instead of hard-thresholding it',
        () {
      // A hard threshold looks decisive and eats the anti-aliased edge of every
      // letter, which is exactly the detail OCR reads.
      final curve = ClassicalRestore.contrastCurve();
      expect(curve[0], 0);
      expect(curve[255], 255);
      final between = <int>[
        for (var i = 0; i < 256; i++)
          if (curve[i] > 8 && curve[i] < 247) i,
      ];
      expect(between.length, greaterThan(20),
          reason: 'the transition must be a ramp, not a cliff');
    });
  });

  group('analysis resolution', () {
    // The first version of this pipeline analysed the full-resolution image
    // and took 56 seconds on a 12 MP photograph, which every unit test missed
    // because the fixtures are 240x320. These tests exercise the path that
    // only appears on a large image.

    /// A page big enough that the analysis actually downscales.
    ImageBuffer largePage(int width, int height) {
      final data = Uint8List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final onLine = (y % 40) < 14 && y > 60 && y < height - 60;
          final inColumn = x > 60 && x < width - 60;
          final shade = 0.5 + 0.5 * (x / width);
          data[y * width + x] =
              (((onLine && inColumn) ? 40 : 245) * shade).round().clamp(0, 255);
        }
      }
      return ImageBuffer.gray(width, height, data);
    }

    double spread(ImageBuffer image, int width, int height) {
      final values = <int>[];
      for (var y = 0; y < height; y++) {
        if ((y % 40) < 18) continue;
        for (var x = 80; x < width - 80; x += 3) {
          values.add(image.data[y * width + x]);
        }
      }
      final mean = values.reduce((a, b) => a + b) / values.length;
      return math.sqrt(
        values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length,
      );
    }

    test('flattens a shadow on an image far larger than the analysis grid', () {
      const width = 1600;
      const height = 1200;
      final before = largePage(width, height);
      final after = const ClassicalRestore()(before);
      expect(
        spread(after, width, height),
        lessThan(spread(before, width, height) / 3),
      );
    });

    test('the answer barely moves when the analysis grid changes size', () {
      // If it did, the default would be a quality setting rather than a
      // performance one, and it is sold as the latter.
      const width = 1600;
      const height = 1200;
      final image = largePage(width, height);

      final coarse = ClassicalRestore(analysisWidth: 256)(image);
      final fine = ClassicalRestore(analysisWidth: 1024)(image);

      var worst = 0;
      var total = 0;
      for (var i = 0; i < coarse.data.length; i++) {
        final difference = (coarse.data[i] - fine.data[i]).abs();
        total += difference;
        if (difference > worst) worst = difference;
      }
      expect(total / coarse.data.length, lessThan(6),
          reason: 'mean difference over 256 grey levels');
      expect(worst, lessThan(80), reason: 'no pixel may be wildly different');
    });

    test('costs roughly the same per pixel whatever the analysis radius', () {
      // The old failure in one assertion: cost used to grow with the blur
      // radius, and the radius grew with the image, so a 15x larger photograph
      // cost 52x more. Timing is coarse here on purpose — this catches a
      // return to quadratic behaviour, not a 20% regression.
      final small = largePage(800, 600);
      final large = largePage(1600, 1200);
      const restore = ClassicalRestore();
      restore(small);

      final smallWatch = Stopwatch()..start();
      restore(small);
      smallWatch.stop();

      final largeWatch = Stopwatch()..start();
      restore(large);
      largeWatch.stop();

      // Four times the pixels must not cost more than twelve times the time.
      expect(
        largeWatch.elapsedMicroseconds,
        lessThan(math.max(smallWatch.elapsedMicroseconds, 1000) * 12),
      );
    });
  });

  group('ImageBuffer', () {
    test('rejects a byte count that does not match its geometry', () {
      expect(
        () =>
            ImageBuffer(width: 4, height: 4, channels: 3, data: Uint8List(10)),
        throwsArgumentError,
      );
    });

    test('round-trips luma for a grayscale image', () {
      final image =
          ImageBuffer.gray(2, 2, Uint8List.fromList(<int>[0, 64, 128, 255]));
      expect(image.toLuma(), image.data);
    });
  });
}
