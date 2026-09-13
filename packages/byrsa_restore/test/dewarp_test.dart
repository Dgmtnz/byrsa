// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:test/test.dart';

/// A source image whose pixel value encodes its own position, so a remap can
/// be checked by reading the answer rather than by eyeballing it.
ImageBuffer ramp(int width, int height) {
  final data = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      data[y * width + x] = (x * 255 / (width - 1)).round();
    }
  }
  return ImageBuffer.gray(width, height, data);
}

/// Builds a grid from a function of normalised output position.
SamplingGrid gridOf(
  int width,
  int height,
  (double, double) Function(double u, double v) map,
) {
  final x = Float32List(width * height);
  final y = Float32List(width * height);
  for (var row = 0; row < height; row++) {
    for (var column = 0; column < width; column++) {
      final u = width == 1 ? 0.0 : column / (width - 1) * 2 - 1;
      final v = height == 1 ? 0.0 : row / (height - 1) * 2 - 1;
      final (gx, gy) = map(u, v);
      x[row * width + column] = gx;
      y[row * width + column] = gy;
    }
  }
  return SamplingGrid(width: width, height: height, x: x, y: y);
}

void main() {
  group('SamplingGrid', () {
    test('reads a channel-planar network output', () {
      // NCHW: every x, then every y. Reading it interleaved is the mistake
      // that produces a page warped diagonally into nonsense.
      final planar = Float32List.fromList(<double>[
        -1, 1, -1, 1, // x for a 2x2 grid
        -1, -1, 1, 1, // y
      ]);
      final grid = SamplingGrid.fromPlanar(planar, width: 2, height: 2);
      expect(grid.x.toList(), <double>[-1, 1, -1, 1]);
      expect(grid.y.toList(), <double>[-1, -1, 1, 1]);
    });

    test('refuses an output that is the wrong size', () {
      expect(
        () => SamplingGrid.fromPlanar(Float32List(6), width: 2, height: 2),
        throwsArgumentError,
      );
    });

    test('the identity grid is the identity', () {
      final grid = SamplingGrid.identity();
      expect(grid.x.toList(), <double>[-1, 1, -1, 1]);
      expect(grid.y.toList(), <double>[-1, -1, 1, 1]);
    });
  });

  group('remapThroughGrid', () {
    test('leaves the image alone when the grid is the identity', () {
      final source = ramp(64, 48);
      final out = remapThroughGrid(source, SamplingGrid.identity());
      for (var i = 0; i < source.data.length; i++) {
        expect(out.data[i], closeTo(source.data[i], 1),
            reason: 'pixel $i drifted');
      }
    });

    test('mirrors the image when the grid mirrors it', () {
      final source = ramp(64, 48);
      final out = remapThroughGrid(
        source,
        gridOf(2, 2, (u, v) => (-u, v)),
      );
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 64; x++) {
          expect(
              out.data[y * 64 + x], closeTo(source.data[y * 64 + (63 - x)], 1));
        }
      }
    });

    test('produces any output size from a tiny grid, which is the whole point',
        () {
      // The real grid is 45x31 and the page is millions of pixels.
      final source = ramp(200, 150);
      final out = remapThroughGrid(
        source,
        SamplingGrid.identity(),
        outputWidth: 800,
        outputHeight: 600,
      );
      expect(out.width, 800);
      expect(out.height, 600);
      // Still a left-to-right ramp, just bigger.
      expect(out.data[300 * 800 + 0], lessThan(20));
      expect(out.data[300 * 800 + 799], greaterThan(235));
    });

    test('interpolates between grid samples instead of stepping', () {
      // A coarse grid with nearest-neighbour lookup shows as visible bands.
      // Along a row the result must increase monotonically, without plateaux
      // the width of a grid cell.
      final source = ramp(256, 8);
      final out = remapThroughGrid(
        source,
        gridOf(5, 5, (u, v) => (u * 0.8, v)),
        outputWidth: 256,
        outputHeight: 8,
      );
      var plateau = 0;
      var worst = 0;
      for (var x = 1; x < 256; x++) {
        final previous = out.data[4 * 256 + x - 1];
        final current = out.data[4 * 256 + x];
        expect(current, greaterThanOrEqualTo(previous));
        plateau = current == previous ? plateau + 1 : 0;
        if (plateau > worst) worst = plateau;
      }
      expect(worst, lessThan(8), reason: 'a flat run that long is a band');
    });

    test('clamps to the edge rather than leaving a black wedge', () {
      // A dewarp that reaches slightly past the paper is normal. Black down
      // the side of the page is not.
      final source = ramp(64, 48);
      final out = remapThroughGrid(
        source,
        gridOf(2, 2, (u, v) => (u * 3, v * 3)),
      );
      expect(out.data.first, source.data.first);
      expect(out.data[47 * 64 + 63], source.data[47 * 64 + 63]);
      expect(out.data.any((v) => v == 0 && source.data.first != 0), isFalse);
    });

    test('carries every channel of a colour page', () {
      final data = Uint8List(4 * 4 * 3);
      for (var i = 0; i < 16; i++) {
        data[i * 3] = 200;
        data[i * 3 + 1] = 100;
        data[i * 3 + 2] = 50;
      }
      final out = remapThroughGrid(
        ImageBuffer(width: 4, height: 4, channels: 3, data: data),
        SamplingGrid.identity(),
      );
      expect(out.channels, 3);
      expect(out.data.sublist(0, 3), <int>[200, 100, 50]);
    });

    test('refuses a zero-sized output instead of returning an empty image', () {
      expect(
        () => remapThroughGrid(ramp(8, 8), SamplingGrid.identity(),
            outputWidth: 0),
        throwsArgumentError,
      );
    });
  });
}
