// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:test/test.dart';

class _Stage implements RestoreStage {
  _Stage(this.id, {this.unavailable, this.throws = false, this.delta = 1});

  @override
  final String id;
  final StageSkipReason? unavailable;
  final bool throws;
  final int delta;
  bool applied = false;

  @override
  Future<StageSkipReason?> unavailableReason() async => unavailable;

  @override
  Future<ImageBuffer> apply(ImageBuffer input) async {
    applied = true;
    if (throws) throw StateError('inference exploded');
    final out =
        Uint8List.fromList(input.data.map((v) => (v + delta) & 0xFF).toList());
    return ImageBuffer.gray(input.width, input.height, out);
  }
}

ImageBuffer flat(int value) =>
    ImageBuffer.gray(4, 4, Uint8List.fromList(List<int>.filled(16, value)));

void main() {
  test('runs stages in order', () async {
    final first = _Stage('a', delta: 1);
    final second = _Stage('b', delta: 10);
    final result =
        await RestorePipeline(<RestoreStage>[first, second]).run(flat(0));

    expect(result.image.data.first, 11);
    expect(result.outcomes.map((o) => o.id), <String>['a', 'b']);
    expect(result.outcomes.every((o) => o.ran), isTrue);
  });

  test('skips a stage that cannot run, and says why', () async {
    // The whole reason the pipeline exists: the same code has to work on an
    // F-Droid install with no models downloaded.
    final skipped =
        _Stage('uvdoc', unavailable: StageSkipReason.modelNotInstalled);
    final result = await RestorePipeline(<RestoreStage>[
      _Stage('classical'),
      skipped,
    ]).run(flat(0));

    expect(skipped.applied, isFalse);
    expect(result.outcomes.last.ran, isFalse);
    expect(result.outcomes.last.skipReason, StageSkipReason.modelNotInstalled);
    expect(result.image.data.first, 1,
        reason: 'the earlier stage still applied');
  });

  test('a stage that throws costs its stage, not the capture', () async {
    final result = await RestorePipeline(<RestoreStage>[
      _Stage('classical', delta: 5),
      _Stage('docshadow', throws: true),
      _Stage('sharpen', delta: 2),
    ]).run(flat(0));

    expect(result.image.data.first, 7, reason: 'the later stage still ran');
    expect(result.outcomes[1].skipReason, StageSkipReason.failed);
    expect(result.outcomes[1].error, isA<StateError>());
  });

  test('reports stages in the shape the evaluation harness reads', () async {
    final result = await RestorePipeline(<RestoreStage>[
      _Stage('classical'),
      _Stage('uvdoc', unavailable: StageSkipReason.unsupportedPlatform),
    ]).run(flat(0));

    final json = result.toStageJson();
    expect(json.first['name'], 'classical');
    expect(json.first.containsKey('skipped'), isFalse);
    expect(json.last['skipped'], true);
    expect(json.last['skipReason'], 'unsupportedPlatform');
  });

  test('the classical stage is never unavailable', () async {
    expect(await const ClassicalStage().unavailableReason(), isNull);
  });
}
