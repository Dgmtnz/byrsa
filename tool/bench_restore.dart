// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// Times the classical restoration at real camera resolutions.
//
//   dart run tool/bench_restore.dart
//
// This exists because the first version of ClassicalRestore took 56 seconds on
// a 12 MP photograph and every unit test passed: the tests use 240x320 images,
// where the cost that mattered was invisible. A behaviour test says the output
// is right. This says it arrives.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';

/// A page with text, a shadow across it and some noise — the work is
/// data-independent, but a realistic histogram keeps CLAHE honest.
ImageBuffer page(int width, int height, {int channels = 1}) {
  final random = math.Random(7);
  final data = Uint8List(width * height * channels);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final line = (y % (height ~/ 60).clamp(4, 40)) < 3;
      final shade = 0.45 + 0.55 * (x / width);
      final value = (((line ? 45 : 240) + random.nextInt(12)) * shade)
          .round()
          .clamp(0, 255);
      final index = (y * width + x) * channels;
      for (var c = 0; c < channels; c++) {
        data[index + c] = value;
      }
    }
  }
  return channels == 1
      ? ImageBuffer.gray(width, height, data)
      : ImageBuffer(width: width, height: height, channels: 3, data: data);
}

void main(List<String> arguments) {
  const sizes = <(int, int, String)>[
    (1000, 750, '0.8 MP'),
    (2000, 1500, '3 MP  '),
    (3024, 4032, '12 MP '),
    (4000, 3000, '12 MP '),
  ];

  for (final channels in <int>[1, 3]) {
    print('\n${channels == 1 ? "grayscale" : "colour   "}   '
        'analysisWidth=512');
    print('  size         megapixels   time     per megapixel');
    for (final (width, height, _) in sizes) {
      final image = page(width, height, channels: channels);
      const restore = ClassicalRestore();
      restore(page(64, 64, channels: channels)); // warm the JIT

      final watch = Stopwatch()..start();
      restore(image);
      final ms = watch.elapsedMilliseconds;
      final mp = width * height / 1e6;
      print('  ${width}x$height'.padRight(15) +
          mp.toStringAsFixed(1).padLeft(8) +
          '${ms}ms'.padLeft(10) +
          '${(ms / mp).toStringAsFixed(0)} ms/MP'.padLeft(16));
    }
  }

  print('\nanalysis width sweep, 12 MP grayscale');
  final big = page(4000, 3000);
  for (final width in <int>[256, 512, 1024, 2048]) {
    final watch = Stopwatch()..start();
    ClassicalRestore(analysisWidth: width)(big);
    print('  analysisWidth=${width.toString().padRight(5)} '
        '${watch.elapsedMilliseconds} ms');
  }
}
