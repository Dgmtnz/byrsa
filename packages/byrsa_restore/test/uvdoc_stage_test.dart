// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:byrsa_restore/byrsa_restore.dart';
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
}
