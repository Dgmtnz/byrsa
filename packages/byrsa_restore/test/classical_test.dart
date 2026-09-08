// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter_test/flutter_test.dart';

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
      values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
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

      int channel(int x, int y, int c) => restored.data[(y * _width + x) * 3 + c];
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

  group('ImageBuffer', () {
    test('rejects a byte count that does not match its geometry', () {
      expect(
        () => ImageBuffer(width: 4, height: 4, channels: 3, data: Uint8List(10)),
        throwsArgumentError,
      );
    });

    test('round-trips luma for a grayscale image', () {
      final image = ImageBuffer.gray(2, 2, Uint8List.fromList(<int>[0, 64, 128, 255]));
      expect(image.toLuma(), image.data);
    });
  });
}
