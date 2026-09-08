// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'classical.dart';
import 'image_buffer.dart';

/// Why a stage did not run.
///
/// A stage that cannot run is normal, not exceptional: a phone with no model
/// downloaded, a device too slow, an iPhone where ONNX turned out not to work.
/// The pipeline records it and carries on, which is what lets the same code
/// path serve an F-Droid install with no models and a fully equipped one
/// (DECISIONS.md D-016).
enum StageSkipReason {
  modelNotInstalled,
  unsupportedPlatform,
  disabledByUser,
  inputTooLarge,
  failed,
}

/// One step of restoration.
abstract class RestoreStage {
  /// Stable identifier. It is what the evaluation harness reports timings
  /// against, so it must not change casually.
  String get id;

  /// Whether this stage can run right now.
  Future<StageSkipReason?> unavailableReason() async => null;

  Future<ImageBuffer> apply(ImageBuffer input);
}

/// What one stage did.
class StageOutcome {
  StageOutcome({
    required this.id,
    required this.duration,
    this.skipReason,
    this.error,
  });

  final String id;
  final Duration duration;
  final StageSkipReason? skipReason;
  final Object? error;

  bool get ran => skipReason == null;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': id,
        'milliseconds': duration.inMicroseconds / 1000,
        if (skipReason != null) 'skipped': true,
        if (skipReason != null) 'skipReason': skipReason!.name,
        if (error != null) 'error': '$error',
      };
}

/// The result of running a pipeline: the image, and an honest account of how
/// it got there.
class RestoreResult {
  RestoreResult(this.image, this.outcomes);

  final ImageBuffer image;
  final List<StageOutcome> outcomes;

  Duration get total => outcomes.fold(
        Duration.zero,
        (sum, outcome) => sum + outcome.duration,
      );

  /// Shaped for the evaluation harness's run file.
  List<Map<String, Object?>> toStageJson() =>
      outcomes.map((o) => o.toJson()).toList(growable: false);
}

/// Runs stages in order, skipping the ones that cannot run.
///
/// A stage that throws is recorded as failed and the pipeline continues with
/// the image as it was. Losing a shadow-removal pass is a worse scan; losing
/// the whole capture is a lost document.
class RestorePipeline {
  const RestorePipeline(this.stages);

  final List<RestoreStage> stages;

  Future<RestoreResult> run(ImageBuffer input) async {
    var image = input;
    final outcomes = <StageOutcome>[];

    for (final stage in stages) {
      final unavailable = await stage.unavailableReason();
      if (unavailable != null) {
        outcomes.add(StageOutcome(
          id: stage.id,
          duration: Duration.zero,
          skipReason: unavailable,
        ));
        continue;
      }
      final watch = Stopwatch()..start();
      try {
        image = await stage.apply(image);
        outcomes.add(StageOutcome(id: stage.id, duration: watch.elapsed));
      } on Object catch (error) {
        outcomes.add(StageOutcome(
          id: stage.id,
          duration: watch.elapsed,
          skipReason: StageSkipReason.failed,
          error: error,
        ));
      }
    }
    return RestoreResult(image, outcomes);
  }
}

/// The classical pipeline as a stage, so it composes with the neural ones.
///
/// It never reports itself unavailable: no model, no download, no native
/// library. That is the point of having it.
class ClassicalStage implements RestoreStage {
  const ClassicalStage([this.restore = const ClassicalRestore()]);

  final ClassicalRestore restore;

  @override
  String get id => 'classical';

  @override
  Future<StageSkipReason?> unavailableReason() async => null;

  @override
  Future<ImageBuffer> apply(ImageBuffer input) async => restore(input);
}
