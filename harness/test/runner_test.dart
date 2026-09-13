// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:byrsa_harness/byrsa_harness.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:test/test.dart';

void main() {
  late Directory corpus;

  setUp(() {
    corpus = Directory.systemTemp.createTempSync('byrsa_corpus');
    const SyntheticCorpus(width: 220, height: 300).write(corpus, count: 2);
  });
  tearDown(() => corpus.deleteSync(recursive: true));

  group('the synthetic corpus', () {
    test('writes a manifest the dataset loader accepts', () {
      final dataset = Dataset.load(corpus);
      expect(dataset.documents, hasLength(2));
      for (final document in dataset.documents) {
        expect(File('${corpus.path}/${document.file}').existsSync(), isTrue);
        expect(document.groundTruthImage, isNotNull);
        expect(
          File('${corpus.path}/${document.groundTruthImage}').existsSync(),
          isTrue,
        );
      }
    });

    test('uses both shadow models, because one of them flatters us', () {
      // A purely multiplicative shadow is exactly what dividing by an estimated
      // background inverts. Measuring only against that would make the
      // classical pipeline look better than it is (D-039).
      final conditions =
          Dataset.load(corpus).documents.expand((d) => d.conditions).toSet();
      expect(
          conditions,
          containsAll(<String>[
            'multiplicative-shadow',
            'physical-shadow',
          ]));
    });

    test('leaves ground-truth text empty rather than inventing it', () {
      // No font is rendered, so no OCR engine could recover text from these.
      // A non-empty file here would be a test that cannot be passed honestly.
      for (final document in Dataset.load(corpus).documents) {
        expect(
          File('${corpus.path}/${document.groundTruth}').readAsStringSync(),
          isEmpty,
        );
      }
    });
  });

  group('psnr', () {
    test('returns null for identical images instead of infinity', () {
      // An infinite score in a report is a bug that looks like a triumph.
      final data = Uint8List.fromList(List<int>.generate(300, (i) => i % 256));
      expect(psnr(data, data), isNull);
    });

    test('falls as the difference grows', () {
      final a = Uint8List(300)..fillRange(0, 300, 200);
      final near = Uint8List(300)..fillRange(0, 300, 202);
      final far = Uint8List(300)..fillRange(0, 300, 120);
      expect(psnr(a, near)!, greaterThan(psnr(a, far)!));
    });

    test('refuses to compare images of different sizes', () {
      expect(psnr(Uint8List(10), Uint8List(12)), isNull);
    });
  });

  group('running the pipeline', () {
    test('restoration measurably improves the page', () {
      // The point of the whole harness, in one assertion: the shipped
      // restoration must move a shadowed capture closer to the clean original.
      final run = const PipelineRunner(writeOutput: false).run(
        Dataset.load(corpus),
        runId: 'test',
        device: 'test',
      );
      expect(run.documents, hasLength(2));
      for (final document in run.documents) {
        expect(document.psnrInput, isNotNull);
        expect(document.psnr, isNotNull);
        expect(
          document.psnrGain,
          greaterThan(3),
          reason: '${document.id} barely changed',
        );
      }
    });

    test('records a stage per step, all of them timed', () {
      final run = const PipelineRunner(writeOutput: false).run(
        Dataset.load(corpus),
        runId: 'test',
        device: 'test',
      );
      final stages = run.documents.first.stages.map((s) => s.name).toList();
      expect(stages, <String>['decode', 'classical:colour', 'encode']);
      expect(run.documents.first.totalMilliseconds, greaterThan(0));
    });

    test('a black and white page is much smaller than a colour one', () {
      final dataset = Dataset.load(corpus);
      int bytes(PageFilter filter) => PipelineRunner(
            filter: filter,
            writeOutput: false,
          ).run(dataset, runId: 't', device: 't').documents.first.outputBytes!;

      expect(
          bytes(PageFilter.blackAndWhite), lessThan(bytes(PageFilter.colour)));
    });

    test('a missing file is a skipped stage, not a crash', () {
      // Half a run is worth having. A dataset with one bad path must not cost
      // the other forty-nine.
      File('${corpus.path}/${Dataset.load(corpus).documents.first.file}')
          .deleteSync();
      final run = const PipelineRunner(writeOutput: false).run(
        Dataset.load(corpus),
        runId: 'test',
        device: 'test',
      );
      expect(run.documents.first.stages.single.skipped, isTrue);
      expect(run.documents.first.stages.single.skipReason, contains('missing'));
      expect(run.documents.last.psnr, isNotNull, reason: 'the rest still ran');
    });

    test('the run it writes is a run it can read back', () {
      // score reads what run writes. If those two drift the tool is two tools.
      final run = const PipelineRunner(writeOutput: false).run(
        Dataset.load(corpus),
        runId: 'round-trip',
        device: 'test host',
      );
      final file = File('${corpus.path}/run.json')
        ..writeAsStringSync(jsonEncode(run.toJson()));
      final reloaded = RunResults.load(file);

      expect(reloaded.runId, 'round-trip');
      expect(reloaded.platform, run.platform);
      expect(reloaded.pipeline, run.pipeline);
      expect(reloaded.documents.first.psnr,
          closeTo(run.documents.first.psnr!, 1e-9));
      expect(reloaded.documents.first.stages, hasLength(3));
    });
  });
}
