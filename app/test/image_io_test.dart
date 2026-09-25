// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa/src/data/image_io.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter_test/flutter_test.dart';

/// That the restore pipeline is built out of the stages the user asked for.
///
/// `IntrusionStage` was finished, exported and covered by 19 tests in
/// `byrsa_restore`, and constructed nowhere in the application — `grep -rn
/// Intrusion app` returned nothing — so "it does not remove fingers" was true
/// of a feature that already existed. What broke was the wiring, so the wiring
/// is what this watches; the algorithm has its own tests.
///
/// Tested on [restoreStages] and not through `ImageIo.restoreFile`, which
/// cannot run here: `BackgroundIsolateBinaryMessenger.ensureInitialized` inside
/// a `compute` isolate dies under `flutter test` with "Callbacks into the Dart
/// VM are currently prohibited".
void main() {
  Iterable<String> ids({
    required bool removeIntrusions,
    String? dewarpModelPath,
  }) =>
      restoreStages(
        filter: PageFilter.colour,
        removeIntrusions: removeIntrusions,
        dewarpModelPath: dewarpModelPath,
      ).map((stage) => stage.id);

  test('the intrusion stage runs when the preference is on', () {
    expect(ids(removeIntrusions: true), contains('intrusion'));
  });

  test('and is not in the pipeline at all when it is off', () {
    expect(ids(removeIntrusions: false), isNot(contains('intrusion')));
  });

  // The order is the decision, not the membership: the detector measures
  // distance from the paper, which is only meaningful once the light has been
  // flattened (D-042).
  test('and always after the classical stage that flattens the light', () {
    expect(ids(removeIntrusions: true), ['classical', 'intrusion']);
    // And geometry before both, which the line above cannot show without a
    // model. Building the stage does not open its file, so the path need not
    // exist.
    expect(ids(removeIntrusions: true, dewarpModelPath: 'uvdoc.onnx'),
        ['uvdoc', 'classical', 'intrusion']);
  });

  test('and the toggle is what reaches it', () {
    // Every hop from the setting to the isolate, read from the source for the
    // reason above. Lose one and the toggle stops reaching the stage, which is
    // D-055's bug again, one call site over.
    final lib = Directory('lib').existsSync() ? 'lib' : 'app/lib';
    final screen = File('$lib/src/ui/document_screen.dart').readAsStringSync();
    final io = File('$lib/src/data/image_io.dart').readAsStringSync();
    void passes(String source, String call, String value) => expect(
          RegExp('$call\\([^;]*removeIntrusions:\\s*$value\\b')
              .hasMatch(source),
          isTrue,
          reason: '$call( no longer passes $value on',
        );

    passes(screen, 'ImageIo', r'preferences\.removeIntrusions');
    passes(io, '_RestoreRequest', 'removeIntrusions');
    passes(io, 'restoreStages', r'request\.removeIntrusions');
  });
}
