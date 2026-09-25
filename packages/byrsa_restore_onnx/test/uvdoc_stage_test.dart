// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:byrsa_restore_onnx/byrsa_restore_onnx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports itself unavailable when the model is not downloaded', () async {
    // The path an F-Droid install takes on first run, and the one that must
    // never throw: a missing model is a skipped stage, not a failed capture.
    final stage =
        UvdocStage(modelFile: File('/does/not/exist/UVDoc_grid.onnx'));
    expect(await stage.unavailableReason(), StageSkipReason.modelNotInstalled);
  });

  test('a pipeline containing it still produces an image without the model',
      () async {
    final input = ImageBuffer.gray(8, 8, null);
    final result = await RestorePipeline(<RestoreStage>[
      UvdocStage(modelFile: File('/does/not/exist/UVDoc_grid.onnx')),
      const ClassicalStage(),
    ]).run(input);

    expect(result.image.width, 8);
    expect(result.outcomes.first.id, 'uvdoc');
    expect(result.outcomes.first.skipReason, StageSkipReason.modelNotInstalled);
    expect(result.outcomes.last.ran, isTrue);
  });

  // The padding arithmetic, which is the part that cannot be exercised without
  // the model and is the part that silently produces a garbage grid when it is
  // wrong. The sizes below are derived by hand from `padFraction = 0.03`:
  // round(496 * 0.03) = 15 across and round(720 * 0.03) = 22 down, leaving a
  // 466x676 page centred in the 496x720 tensor.
  const padX = 15;
  const padY = 22;
  const pageWidth = UvdocStage.inputWidth - padX * 2;
  const pageHeight = UvdocStage.inputHeight - padY * 2;

  double at(Float32List tensor, int plane, int x, int y) =>
      tensor[plane * UvdocStage.inputWidth * UvdocStage.inputHeight +
          y * UvdocStage.inputWidth +
          x];

  test('the model input puts the page inside a border of background', () {
    // One flat colour: a bilinear resize of a constant is that constant, so
    // every pixel of the page is exactly this and anything that is not is
    // border — which is what makes the rectangle's edges checkable to the pixel.
    final image = ImageBuffer(
      width: 4,
      height: 4,
      channels: 3,
      data: Uint8List.fromList(
        List<int>.generate(4 * 4 * 3, (i) => <int>[200, 100, 50][i % 3]),
      ),
    );

    final tensor = UvdocStage.toModelInput(image);
    expect(
      tensor.length,
      UvdocStage.inputWidth * UvdocStage.inputHeight * 3,
    );

    // Planar, not interleaved: each channel is its own full-size plane.
    for (final plane in <int>[0, 1, 2]) {
      final paper = <double>[200 / 255, 100 / 255, 50 / 255][plane];

      // The four corners of the page, and the pixel just outside each of them.
      expect(at(tensor, plane, padX, padY), closeTo(paper, 1e-6));
      expect(
        at(tensor, plane, padX + pageWidth - 1, padY + pageHeight - 1),
        closeTo(paper, 1e-6),
      );
      expect(at(tensor, plane, padX - 1, padY), 0.5);
      expect(at(tensor, plane, padX, padY - 1), 0.5);
      expect(at(tensor, plane, padX + pageWidth, padY + pageHeight - 1), 0.5);
      expect(at(tensor, plane, padX + pageWidth - 1, padY + pageHeight), 0.5);

      // And the tensor's own corner, which is border all the way round.
      expect(at(tensor, plane, 0, 0), 0.5);
      expect(
        at(tensor, plane, UvdocStage.inputWidth - 1,
            UvdocStage.inputHeight - 1),
        0.5,
      );
    }
  });

  test('the grid comes back in the page\'s coordinates, not the canvas\'s', () {
    // The network answers in the padded canvas's frame. With
    // `align_corners = true` the page's left edge sits at canvas pixel 15 of
    // 495, so the network reports it as 2 * 15 / 495 - 1; the page's own frame
    // has to call that -1. Same going down: canvas pixel 22 of 719.
    final leftEdge = 2 * padX / (UvdocStage.inputWidth - 1) - 1;
    final rightEdge =
        2 * (UvdocStage.inputWidth - 1 - padX) / (UvdocStage.inputWidth - 1) -
            1;
    final topEdge = 2 * padY / (UvdocStage.inputHeight - 1) - 1;
    final bottomEdge =
        2 * (UvdocStage.inputHeight - 1 - padY) / (UvdocStage.inputHeight - 1) -
            1;

    expect(leftEdge, closeTo(-0.9393939, 1e-6));
    expect(topEdge, closeTo(-0.9388039, 1e-6));

    // [1, 2, 3, 3], channel 0 x and channel 1 y, exactly as the export emits.
    final output = <List<List<List<double>>>>[
      <List<List<double>>>[
        <List<double>>[
          <double>[leftEdge, 0, rightEdge],
          <double>[leftEdge, 0, rightEdge],
          <double>[leftEdge, 0, rightEdge],
        ],
        <List<double>>[
          <double>[topEdge, topEdge, topEdge],
          <double>[0, 0, 0],
          <double>[bottomEdge, bottomEdge, bottomEdge],
        ],
      ],
    ];

    final grid = UvdocStage.toGrid(output);
    expect(grid.width, 3);
    expect(grid.height, 3);
    for (var row = 0; row < 3; row++) {
      expect(grid.x[row * 3], closeTo(-1, 1e-6));
      expect(grid.x[row * 3 + 1], closeTo(0, 1e-6));
      expect(grid.x[row * 3 + 2], closeTo(1, 1e-6));
    }
    for (var column = 0; column < 3; column++) {
      expect(grid.y[column], closeTo(-1, 1e-6));
      expect(grid.y[3 + column], closeTo(0, 1e-6));
      expect(grid.y[6 + column], closeTo(1, 1e-6));
    }
  });

  test(
      'the resized page samples every row and column instead of quantising '
      'to 257 levels', () {
    // Regression test for the identity-grid quantisation bug: a bare
    // `SamplingGrid.identity()` is a 2x2 grid, so `_axisWeights` rounded
    // every sample position to one of 257 fixed-point levels per axis and
    // most tensor rows and columns duplicated their neighbour instead of
    // resizing the page. Seeded noise makes a duplicate row or column
    // (near-)impossible unless the resize is broken.
    const sourceWidth = 2250, sourceHeight = 3000;
    final rnd = math.Random(1);
    final data = Uint8List(sourceWidth * sourceHeight);
    for (var i = 0; i < data.length; i++) {
      data[i] = rnd.nextInt(256);
    }
    final page = ImageBuffer(
      width: sourceWidth,
      height: sourceHeight,
      channels: 1,
      data: data,
    );
    final tensor = UvdocStage.toModelInput(page);

    for (var y = padY + 1; y < padY + pageHeight; y++) {
      var identical = true;
      for (var x = padX; x < padX + pageWidth && identical; x++) {
        if (at(tensor, 0, x, y) != at(tensor, 0, x, y - 1)) identical = false;
      }
      expect(identical, isFalse,
          reason: 'tensor row $y duplicates the row above it');
    }
    for (var x = padX + 1; x < padX + pageWidth; x++) {
      var identical = true;
      for (var y = padY; y < padY + pageHeight && identical; y++) {
        if (at(tensor, 0, x, y) != at(tensor, 0, x - 1, y)) identical = false;
      }
      expect(identical, isFalse,
          reason: 'tensor column $x duplicates the column to its left');
    }

    // An output-sized identity grid is an exact align_corners bilinear
    // resize, so the page's first and last source pixel land exactly on the
    // page region's corners in the tensor.
    expect(at(tensor, 0, padX, padY), closeTo(data[0] / 255, 1e-6));
    final lastPixel =
        data[(sourceHeight - 1) * sourceWidth + (sourceWidth - 1)] / 255;
    expect(
      at(tensor, 0, padX + pageWidth - 1, padY + pageHeight - 1),
      closeTo(lastPixel, 1e-6),
    );
  });

  test('a grid that is not two channels is refused by name', () {
    // The image-output export of the same network returns three, and the
    // difference is invisible until the page comes out as mush.
    expect(
      () => UvdocStage.toGrid(<List<List<List<double>>>>[
        <List<List<double>>>[
          <List<double>>[
            <double>[0]
          ],
          <List<double>>[
            <double>[0]
          ],
          <List<double>>[
            <double>[0]
          ],
        ],
      ]),
      throwsStateError,
    );
  });
}
