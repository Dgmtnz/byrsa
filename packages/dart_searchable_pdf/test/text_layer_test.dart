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
  group('WinAnsi codes', () {
    test('printable ASCII encodes to itself, space and hyphen included', () {
      // Every code point from 0x20 to 0x7E is its own WinAnsi byte. Two were
      // not: the space came out as 0xA0 and the hyphen as 0xAD — the
      // non-breaking and soft variants, which render identically and so are
      // invisible on the page.
      //
      // Nothing caught it, because the round-trip tests read the file back with
      // `pdftotext`, and Poppler normalises both to their plain forms on
      // extraction. It surfaced in a document title, which gets no such
      // normalisation, on a PDF exported from a phone: "Importado 2026-09-14"
      // came back as "Importado€2026<?>09<?>14".
      //
      // So this asserts the bytes rather than the text. A test that reads the
      // text back would still pass with the bug in place.
      for (var code = 0x20; code <= 0x7E; code++) {
        final character = String.fromCharCode(code);
        expect(
          encodeWinAnsi(character),
          <int>[code],
          reason: 'U+${code.toRadixString(16).padLeft(4, '0')} "$character"',
        );
      }
    });

    test('a space is a space and not the non-breaking one', () {
      expect(encodeWinAnsi(' '), <int>[0x20]);
      expect(encodeWinAnsi('\u00A0'), <int>[0xA0]);
    });

    test('a hyphen is a hyphen and not the soft one', () {
      expect(encodeWinAnsi('-'), <int>[0x2D]);
      expect(encodeWinAnsi('\u00AD'), <int>[0xAD]);
    });

    test('a phrase encodes with real spaces between its words', () {
      expect(
        encodeWinAnsi('a b'),
        <int>[0x61, 0x20, 0x62],
        reason: 'a searcher looking for "a b" has to find the space it typed',
      );
    });
  });

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
