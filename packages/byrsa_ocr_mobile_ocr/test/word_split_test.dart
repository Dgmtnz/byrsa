// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_ocr_mobile_ocr/byrsa_ocr_mobile_ocr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ocr/mobile_ocr.dart';

List<Offset> box(double left, double top, double right, double bottom) =>
    <Offset>[
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
      Offset(left, bottom),
    ];

CharacterBox character(String text, double left, double right) => CharacterBox(
      text: text,
      confidence: 0.9,
      points: box(left, 100, right, 140),
    );

void main() {
  group('splitting a detected block into words', () {
    // Both engines return one polygon per block, which is often a whole line.
    // A searchable PDF needs a box per word, or the selection drifts along the
    // line and copy-paste comes out misaligned.

    test('a single-word block keeps the block box exactly', () {
      final words = MobileOcrEngine.blockToWords(
        TextBlock(
          text: 'FACTURA',
          confidence: 0.99,
          points: box(120, 200, 420, 260),
          characters: const <CharacterBox>[],
        ),
      );
      expect(words, hasLength(1));
      expect(words.single.text, 'FACTURA');
      expect(words.single.box, const OcrBox(120, 200, 420, 260));
    });

    test(
        'several words are laid across the block in order, without overlapping',
        () {
      final words = MobileOcrEngine.blockToWords(
        TextBlock(
          text: 'Importe total 1.234,56',
          confidence: 0.95,
          points: box(100, 100, 700, 140),
          characters: const <CharacterBox>[],
        ),
      );

      expect(
          words.map((w) => w.text), <String>['Importe', 'total', '1.234,56']);
      expect(words.first.box.left, 100);
      expect(words.last.box.right, closeTo(700, 1e-9));
      for (var i = 1; i < words.length; i++) {
        expect(
          words[i].box.left,
          greaterThanOrEqualTo(words[i - 1].box.right),
          reason: 'word $i must start after the previous one ends',
        );
      }
      // Wider words get wider boxes — the approximation, but a monotonic one.
      expect(words[2].box.width, greaterThan(words[1].box.width));
    });

    test('character boxes win over the proportional guess when present', () {
      final words = MobileOcrEngine.blockToWords(
        TextBlock(
          text: 'ab cd',
          confidence: 0.9,
          points: box(0, 100, 400, 140),
          characters: <CharacterBox>[
            character('a', 10, 40),
            character('b', 40, 70),
            character(' ', 70, 200),
            character('c', 200, 230),
            character('d', 230, 260),
          ],
        ),
      );

      expect(words.map((w) => w.text), <String>['ab', 'cd']);
      // Taken from the characters, not from dividing the block evenly.
      expect(words.first.box, const OcrBox(10, 100, 70, 140));
      expect(words.last.box, const OcrBox(200, 100, 260, 140));
    });

    test('falls back to the proportional split when the characters are useless',
        () {
      final words = MobileOcrEngine.blockToWords(
        TextBlock(
          text: 'hola mundo',
          confidence: 0.9,
          points: box(0, 0, 100, 20),
          characters: <CharacterBox>[character(' ', 0, 1)],
        ),
      );
      expect(words.map((w) => w.text), <String>['hola', 'mundo']);
    });

    test('an empty block produces nothing rather than an empty word', () {
      expect(
        MobileOcrEngine.blockToWords(
          TextBlock(
            text: '   ',
            confidence: 0.9,
            points: box(0, 0, 10, 10),
            characters: const <CharacterBox>[],
          ),
        ),
        isEmpty,
      );
    });

    test('averages character confidence across a word', () {
      final words = MobileOcrEngine.blockToWords(
        TextBlock(
          text: 'ab',
          confidence: 0.5,
          points: box(0, 100, 100, 140),
          characters: <CharacterBox>[
            CharacterBox(
                text: 'a', confidence: 0.6, points: box(0, 100, 50, 140)),
            CharacterBox(
                text: 'b', confidence: 1.0, points: box(50, 100, 100, 140)),
          ],
        ),
      );
      expect(words.single.confidence, closeTo(0.8, 1e-9));
    });
  });
}
