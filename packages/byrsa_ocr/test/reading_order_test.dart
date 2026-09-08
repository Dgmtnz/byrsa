// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

OcrWord word(String text, double left, double top, {double width = 60, double height = 20, double confidence = 0.9}) =>
    OcrWord(
      text: text,
      box: OcrBox(left, top, left + width, top + height),
      confidence: confidence,
    );

void main() {
  group('ReadingOrder', () {
    test('rebuilds lines from boxes the detector returned in any order', () {
      // Detectors return boxes in network order. A page that reads correctly on
      // screen and pastes as scrambled text is the usual symptom of skipping
      // this step.
      final lines = const ReadingOrder().group(<OcrWord>[
        word('mundo', 100, 10),
        word('adios', 20, 60),
        word('hola', 20, 10),
        word('mundo', 100, 60),
      ]);

      expect(lines.map((l) => l.text), <String>['hola mundo', 'adios mundo']);
    });

    test('keeps words on one line when their boxes are not exactly aligned', () {
      // Real boxes wobble by a few pixels; a strict comparison splits a line in
      // two and the PDF pastes with a stray newline in the middle of a sentence.
      final lines = const ReadingOrder().group(<OcrWord>[
        word('Importe', 20, 100, height: 22),
        word('total', 90, 103, height: 19),
        word('1.234,56', 160, 101, height: 21),
      ]);
      expect(lines, hasLength(1));
      expect(lines.single.text, 'Importe total 1.234,56');
    });

    test('separates lines that genuinely do not overlap', () {
      final lines = const ReadingOrder().group(<OcrWord>[
        word('primera', 20, 10),
        word('segunda', 20, 45),
      ]);
      expect(lines, hasLength(2));
    });

    test('drops low-confidence noise when asked, and only then', () {
      final words = <OcrWord>[
        word('bueno', 20, 10, confidence: 0.95),
        word('|||', 90, 10, confidence: 0.2),
      ];
      expect(const ReadingOrder().group(words).single.text, 'bueno |||');
      expect(
        const ReadingOrder(minimumConfidence: 0.5).group(words).single.text,
        'bueno',
      );
    });

    test('ignores empty and whitespace-only detections', () {
      final lines = const ReadingOrder().group(<OcrWord>[
        word('hola', 20, 10),
        word('   ', 90, 10),
      ]);
      expect(lines.single.words, hasLength(1));
    });

    test('produces a line box that covers all of its words', () {
      final line = const ReadingOrder().group(<OcrWord>[
        word('a', 20, 10, width: 30),
        word('b', 100, 12, width: 40, height: 26),
      ]).single;
      expect(line.box.left, 20);
      expect(line.box.right, 140);
      expect(line.box.top, 10);
      expect(line.box.bottom, 38);
    });

    test('averages confidence across a line', () {
      final line = const ReadingOrder().group(<OcrWord>[
        word('a', 20, 10, confidence: 0.6),
        word('b', 100, 10, confidence: 1.0),
      ]).single;
      expect(line.confidence, closeTo(0.8, 1e-9));
    });
  });

  group('OcrResult', () {
    test('joins lines with newlines and words with spaces', () {
      final result = OcrResult(
        lines: const ReadingOrder().group(<OcrWord>[
          word('hola', 20, 10),
          word('mundo', 90, 10),
          word('adios', 20, 60),
        ]),
        imageWidth: 800,
        imageHeight: 600,
        engine: 'pp-ocr-onnx',
        duration: const Duration(milliseconds: 700),
      );
      expect(result.text, 'hola mundo\nadios');
      expect(result.words, hasLength(3));
    });
  });

  group('OcrBox', () {
    test('bounds an arbitrary polygon, which is what detectors return', () {
      final box = OcrBox.ofPolygon(const <({double x, double y})>[
        (x: 10, y: 20),
        (x: 90, y: 14),
        (x: 94, y: 48),
        (x: 12, y: 54),
      ]);
      expect(box, const OcrBox(10, 14, 94, 54));
    });

    test('measures vertical overlap relative to the smaller box', () {
      const tall = OcrBox(0, 0, 10, 40);
      const short = OcrBox(0, 10, 10, 30);
      expect(tall.verticalOverlap(short), 1.0);
      expect(tall.verticalOverlap(const OcrBox(0, 60, 10, 80)), 0.0);
    });
  });
}
