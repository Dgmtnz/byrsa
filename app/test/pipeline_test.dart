// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:byrsa/src/domain/pipeline.dart';
import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter_test/flutter_test.dart';

/// A solid grey PNG, built here so the repository stays free of binaries.
Uint8List greyPng(int width, int height, {int value = 0xF2}) {
  final raw = Uint8List((width + 1) * height);
  for (var y = 0; y < height; y++) {
    raw.fillRange(y * (width + 1) + 1, (y + 1) * (width + 1), value);
  }
  List<int> u32(int v) =>
      <int>[v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];
  final table = List<int>.generate(256, (i) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final byte in data) {
      c = table[(c ^ byte) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  List<int> chunk(String type, List<int> body) {
    final payload = <int>[...type.codeUnits, ...body];
    return <int>[...u32(body.length), ...payload, ...u32(crc(payload))];
  }

  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', <int>[...u32(width), ...u32(height), 8, 0, 0, 0, 0]),
    ...chunk('IDAT', ZLibEncoder().convert(raw)),
    ...chunk('IEND', const <int>[]),
  ]);
}

OcrResult fakeOcr(List<String> lines) {
  final words = <OcrWord>[];
  for (var row = 0; row < lines.length; row++) {
    var x = 100.0;
    final top = 200 + row * 60.0;
    for (final text in lines[row].split(' ')) {
      final width = text.length * 24.0;
      words.add(OcrWord(
        text: text,
        box: OcrBox(x, top, x + width, top + 40),
        confidence: 0.95,
      ));
      x += width + 12;
    }
  }
  return OcrResult(
    lines: const ReadingOrder().group(words),
    imageWidth: 1240,
    imageHeight: 1754,
    engine: 'test',
    duration: const Duration(milliseconds: 5),
  );
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('byrsa_pipeline'));
  tearDown(() => dir.deleteSync(recursive: true));

  DocumentPipeline pipeline({
    Future<OcrResult> Function(String)? recognise,
    List<RestoreStage> stages = const <RestoreStage>[ClassicalStage()],
  }) =>
      DocumentPipeline(
        restore: RestorePipeline(stages),
        recognise: recognise,
        readImage: (path) async => ImageBuffer.gray(
          40,
          40,
          Uint8List.fromList(List<int>.generate(1600, (i) => (i * 7) % 256)),
        ),
        writeImage: (image, path) async {
          await File(path).writeAsBytes(image.data);
          return path;
        },
      );

  test('processes a page and reports every stage it ran', () async {
    final result =
        await pipeline(recognise: (_) async => fakeOcr(<String>['hola']))
            .processPage(
      originalPath: '${dir.path}/in.jpg',
      outputPath: '${dir.path}/out.raw',
    );

    expect(File(result.processedPath).existsSync(), isTrue);
    expect(result.stages.map((s) => s.id),
        containsAll(<String>['decode', 'classical', 'encode', 'ocr']));
    expect(result.stages.every((s) => s.ran), isTrue);
    expect(result.text, 'hola');
  });

  test('records OCR as skipped rather than pretending it ran', () async {
    final result = await pipeline().processPage(
      originalPath: '${dir.path}/in.jpg',
      outputPath: '${dir.path}/out.raw',
    );
    final ocr = result.stages.firstWhere((s) => s.id == 'ocr');
    expect(ocr.ran, isFalse);
    expect(ocr.skipReason, StageSkipReason.disabledByUser);
    expect(result.text, isEmpty);
  });

  test('an OCR failure costs the text, not the page', () async {
    final result = await pipeline(
      recognise: (_) async => throw StateError('model missing'),
    ).processPage(
      originalPath: '${dir.path}/in.jpg',
      outputPath: '${dir.path}/out.raw',
    );
    expect(File(result.processedPath).existsSync(), isTrue);
    expect(result.stages.firstWhere((s) => s.id == 'ocr').skipReason,
        StageSkipReason.failed);
  });

  test('emits a stage record the evaluation harness can score directly',
      () async {
    final result =
        await pipeline(recognise: (_) async => fakeOcr(<String>['hola mundo']))
            .processPage(
      originalPath: '${dir.path}/in.jpg',
      outputPath: '${dir.path}/out.raw',
    );

    final json = result.toHarnessJson('receipt-01', outputBytes: 1234);
    expect(json['id'], 'receipt-01');
    expect(json['text'], 'hola mundo');
    expect(json['outputBytes'], 1234);
    expect((json['stages']! as List).first, containsPair('name', 'decode'));
  });

  // The whole point of the stack, end to end, on a laptop: an image plus
  // recognised words becomes a PDF whose text a third-party reader gets back.
  test('builds a PDF whose text Poppler can read back out', () async {
    final bytes = DocumentPipeline.buildPdf(
      <PdfPageInput>[
        PdfPageInput(
          imageBytes: greyPng(1240, 1754),
          words: fakeOcr(<String>[
            'Factura numero 2026-0042',
            'Importe total 1.234,56 EUR',
          ]).words,
          dpi: 150,
        ),
      ],
      title: 'Factura',
      creationDate: DateTime.utc(2026),
    );

    final file = File('${dir.path}/out.pdf')..writeAsBytesSync(bytes);
    final result = Process.runSync(
      'pdftotext',
      <String>['-layout', file.path, '-'],
      stdoutEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout as String, contains('2026-0042'));
    expect(result.stdout as String, contains('1.234,56'));
  }, skip: _popplerMissing);
}

final String? _popplerMissing = () {
  try {
    return Process.runSync('pdftotext', <String>['-v']).exitCode == 0
        ? null
        : 'pdftotext is not usable';
  } on ProcessException {
    return 'pdftotext (poppler-utils) is not installed';
  }
}();
