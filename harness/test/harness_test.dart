// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:byrsa_harness/byrsa_harness.dart';
import 'package:test/test.dart';

Directory _dataset(Map<String, String> groundTruth) {
  final dir = Directory.systemTemp.createTempSync('byrsa_harness');
  final documents = <Map<String, Object?>>[];
  groundTruth.forEach((id, text) {
    File('${dir.path}/$id.txt').writeAsStringSync(text);
    File('${dir.path}/$id.jpg').writeAsBytesSync(const <int>[0xFF, 0xD8, 0xFF]);
    documents.add(<String, Object?>{
      'id': id,
      'file': '$id.jpg',
      'groundTruth': '$id.txt',
      'category': 'receipt',
      'language': 'es',
      'conditions': <String>['low-light'],
      'publish': true,
      'license': 'CC-BY-4.0',
    });
  });
  File('${dir.path}/manifest.json').writeAsStringSync(
      jsonEncode(<String, Object?>{'version': 1, 'documents': documents}));
  return dir;
}

File _run(Directory dir, Map<String, String> texts) {
  final file = File('${dir.path}/run.json');
  file.writeAsStringSync(jsonEncode(<String, Object?>{
    'run': <String, Object?>{
      'id': 'test-run',
      'device': 'Pixel 6a, Android 14',
      'platform': 'android',
      'pipeline': <String>['capture', 'restore', 'ocr'],
    },
    'documents': <Object?>[
      for (final entry in texts.entries)
        <String, Object?>{
          'id': entry.key,
          'text': entry.value,
          'stages': <Object?>[
            <String, Object?>{'name': 'restore', 'milliseconds': 300},
            <String, Object?>{'name': 'ocr', 'milliseconds': 700},
          ],
        }
    ],
  }));
  return file;
}

void main() {
  group('error rates', () {
    test('are zero for an exact match', () {
      expect(characterErrorRate('hola mundo', 'hola mundo').rate, 0);
      expect(wordErrorRate('hola mundo', 'hola mundo').rate, 0);
    });

    test('count each edit once', () {
      // One substitution in ten characters.
      expect(characterErrorRate('0123456789', '012345678X').rate,
          closeTo(0.1, 1e-9));
      // One deletion and one insertion out of three words.
      expect(wordErrorRate('a b c', 'a c').rate, closeTo(1 / 3, 1e-9));
    });

    test('ignore line-break differences unless asked not to', () {
      expect(characterErrorRate('a\nb', 'a b').rate, 0);
      expect(
          characterErrorRate('a\nb', 'a b', strict: true).rate, greaterThan(0));
    });

    test('handle an empty hypothesis as a total miss', () {
      expect(characterErrorRate('hola', '').rate, 1);
    });

    test('aggregate by weight, not by average of averages', () {
      // A 100-character document with 1 error and a 2-character one with 2
      // errors is 3/102, not the mean of 1% and 100%.
      final total = const ErrorRate(1, 100) + const ErrorRate(2, 2);
      expect(total.rate, closeTo(3 / 102, 1e-9));
    });
  });

  group('scoring a run', () {
    test('counts a document the run never produced as a complete failure', () {
      final dir = _dataset(<String, String>{'a': 'hola mundo', 'b': 'adios'});
      addTearDown(() => dir.deleteSync(recursive: true));

      final card = score(
        Dataset.load(dir),
        RunResults.load(_run(dir, <String, String>{'a': 'hola mundo'})),
      );

      expect(card.missingCount, 1);
      expect(card.scores.firstWhere((s) => s.document.id == 'b').cer!.rate, 1);
      // 0 errors out of 10, plus 5 out of 5.
      expect(card.overallCer!.rate, closeTo(5 / 15, 1e-9));
    });

    test('a run with no OCR engine is not measured, rather than scored 100%',
        () {
      // `harness run` on a desktop produces a result per document with an empty
      // text field, because the recogniser is a platform plugin. Scoring that
      // against a real reference gives exactly 100% for every document, and a
      // page of 100% figures reads as a measured catastrophe instead of as a
      // measurement that never happened. Same rule as `psnr` returning null
      // instead of infinity.
      final dir = _dataset(<String, String>{'a': 'hola mundo', 'b': 'adios'});
      addTearDown(() => dir.deleteSync(recursive: true));

      final card = score(
        Dataset.load(dir),
        RunResults.load(_run(dir, <String, String>{'a': '', 'b': ''})),
      );

      expect(card.missingCount, 0, reason: 'both documents were produced');
      expect(card.measuredCount, 0, reason: 'but neither was read');
      expect(card.scores.every((s) => s.cer == null), isTrue);
      expect(card.overallCer, isNull);
    });

    test('reports the platform it was measured on, prominently', () {
      final dir = _dataset(<String, String>{'a': 'hola'});
      addTearDown(() => dir.deleteSync(recursive: true));
      final card = score(Dataset.load(dir),
          RunResults.load(_run(dir, <String, String>{'a': 'hola'})));

      final markdown = renderMarkdown(card);
      expect(markdown, contains('**android**'));
      expect(markdown, contains('measured on **android**'));
      expect(markdown, contains('Pixel 6a'));
    });

    test('renders CSV and JSON with one row per document', () {
      final dir = _dataset(<String, String>{'a': 'hola', 'b': 'adios'});
      addTearDown(() => dir.deleteSync(recursive: true));
      final card = score(
        Dataset.load(dir),
        RunResults.load(_run(dir, <String, String>{'a': 'hola', 'b': 'adios'})),
      );

      expect(const LineSplitter().convert(renderCsv(card)).length, 3);
      final json = jsonDecode(renderJson(card)) as Map<String, Object?>;
      expect((json['documents']! as List), hasLength(2));
      expect((json['overall']! as Map)['cer'], 0);
    });

    test('adds up stage timings across documents', () {
      final dir = _dataset(<String, String>{'a': 'hola', 'b': 'adios'});
      addTearDown(() => dir.deleteSync(recursive: true));
      final card = score(
        Dataset.load(dir),
        RunResults.load(_run(dir, <String, String>{'a': 'hola', 'b': 'adios'})),
      );

      expect(card.stageTimings['ocr']!.total, 1400);
      expect(card.stageTimings['ocr']!.count, 2);
      expect(card.medianMilliseconds, 1000);
    });
  });
}
