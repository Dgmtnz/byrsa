// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';
import 'package:dart_searchable_pdf/src/font_metrics.dart';
import 'package:test/test.dart';

/// Width of [codes] as a viewer would compute it, in points.
double renderedWidth(PlacedWord word) {
  var advance = 0;
  for (final code in word.codes) {
    advance += helveticaWidths[code];
  }
  return advance / 1000 * word.fontSize * word.horizontalScale / 100;
}

void main() {
  group('font metrics', () {
    test('match Adobe Helvetica', () {
      expect(helveticaWidths[0x20], 278, reason: 'space');
      expect(helveticaWidths[0x41], 667, reason: 'A');
      expect(helveticaWidths[0x69], 222, reason: 'i');
      expect(helveticaWidths[0x57], 944, reason: 'W');
      expect(helveticaSpan, 925);
    });

    test('cover the six languages milestone M5 targets', () {
      const sample = 'áéíóúñÑüÜçÇàèìòùâêîôûäëïöüãõÀÉÎÕÜ ¿¡ªº€';
      final warnings = <String>[];
      final codes = encodeWinAnsi(sample, onWarning: warnings.add);
      expect(warnings, isEmpty, reason: warnings.join('\n'));
      expect(codes.length, sample.runes.length);
      expect(codes, isNot(contains(kUnencodableByte)));
    });

    test('report, rather than hide, a character they cannot encode', () {
      final warnings = <String>[];
      final codes = encodeWinAnsi('中', onWarning: warnings.add);
      expect(codes, <int>[kUnencodableByte]);
      expect(warnings.single, contains('U+4E2D'));
    });
  });

  group('placeWord', () {
    // This is the trap §4.5 of the plan names: text that is selectable but
    // whose selection does not line up with the image. The invariant is that
    // the rendered width equals the width of the OCR box.
    test('fills the box exactly, whatever the word', () {
      const cases = <String>['Total', 'i', 'WWWW', 'Facturación', '1.234,56 €'];
      for (final text in cases) {
        for (final width in <double>[20, 140, 900]) {
          final word = PdfWord(text, PdfRect(100, 200, 100 + width, 240));
          final placed = placeWord(
            word,
            pointsPerPixel: 72 / 300,
            imageHeightPx: 3000,
          )!;
          expect(
            renderedWidth(placed),
            closeTo(width * 72 / 300, 1e-9),
            reason: '"$text" in a ${width}px box',
          );
        }
      }
    });

    test('puts the baseline one descender above the box bottom', () {
      const imageHeight = 1000;
      final word = PdfWord('Ay', const PdfRect(0, 100, 200, 140));
      final placed = placeWord(
        word,
        pointsPerPixel: 1,
        imageHeightPx: imageHeight,
      )!;

      // Box bottom is 140px from the top, so 860pt from the bottom.
      const boxBottomInPdf = imageHeight - 140.0;
      expect(placed.baselineY, greaterThan(boxBottomInPdf));
      expect(
        placed.baselineY - boxBottomInPdf,
        closeTo(-helveticaDescender / 1000 * placed.fontSize, 1e-9),
      );
      // Ascender top must land on the box top, 900pt from the bottom.
      expect(
        placed.baselineY + helveticaAscender / 1000 * placed.fontSize,
        closeTo(imageHeight - 100.0, 1e-9),
      );
    });

    test('scales the font size with the box height, not the text', () {
      final short = placeWord(
        const PdfWord('x', PdfRect(0, 0, 100, 20)),
        pointsPerPixel: 1,
        imageHeightPx: 100,
      )!;
      final tall = placeWord(
        const PdfWord('x', PdfRect(0, 0, 100, 40)),
        pointsPerPixel: 1,
        imageHeightPx: 100,
      )!;
      expect(tall.fontSize, closeTo(short.fontSize * 2, 1e-9));
    });

    test('drops words that cannot be placed instead of emitting nonsense', () {
      const args = (pointsPerPixel: 1.0, imageHeightPx: 100);
      expect(
        placeWord(const PdfWord('  ', PdfRect(0, 0, 10, 10)),
            pointsPerPixel: args.pointsPerPixel,
            imageHeightPx: args.imageHeightPx),
        isNull,
      );
      expect(
        placeWord(const PdfWord('a', PdfRect(0, 0, 0, 10)),
            pointsPerPixel: args.pointsPerPixel,
            imageHeightPx: args.imageHeightPx),
        isNull,
      );
    });

    test('clamps and warns on an impossible box rather than degenerating', () {
      final warnings = <String>[];
      final placed = placeWord(
        // A hundred characters crammed into two points wide.
        PdfWord('m' * 100, const PdfRect(0, 0, 2, 40)),
        pointsPerPixel: 1,
        imageHeightPx: 100,
        onWarning: warnings.add,
      )!;
      expect(placed.horizontalScale, kMinHorizontalScale);
      expect(warnings.single, contains('clamped'));
    });
  });
}
