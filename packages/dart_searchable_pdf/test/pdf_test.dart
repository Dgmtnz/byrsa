// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';
import 'package:dart_searchable_pdf/src/writer.dart';
import 'package:test/test.dart';

import 'helpers/make_png.dart';

/// Lays words out on a grid, the way a page of text roughly looks.
List<PdfWord> _lines(List<String> lines, {double lineHeight = 60}) {
  final words = <PdfWord>[];
  for (var row = 0; row < lines.length; row++) {
    var x = 100.0;
    final top = 200 + row * lineHeight;
    for (final text in lines[row].split(' ')) {
      final width = text.length * 24.0;
      words.add(PdfWord(text, PdfRect(x, top, x + width, top + 40)));
      x += width + 12;
    }
  }
  return words;
}

void main() {
  group('writer primitives', () {
    test('formats numbers without exponents or trailing zeros', () {
      expect(pdfNum(1), '1');
      expect(pdfNum(1.5), '1.5');
      expect(pdfNum(0.000001), '0');
      expect(pdfNum(-12.34000), '-12.34');
      expect(pdfNum(1e9 + 0.5), isNot(contains('e')));
    });

    test('escapes the three characters that can break a literal string', () {
      expect(pdfLiteralString(utf8.encode(r'a(b)c\d')), r'(a\(b\)c\\d)');
    });

    test('writes high bytes as octal so the file stays 7-bit', () {
      expect(pdfLiteralString(<int>[0xE9]), r'(\351)');
      expect(pdfLiteralString(<int>[0x0A]), r'(\012)');
    });
  });

  group('document structure', () {
    late Uint8List bytes;

    setUpAll(() {
      bytes = (SearchablePdf(
        title: 'Recibo',
        creationDate: DateTime.utc(2026, 9, 8, 12),
      )..addPage(SearchablePage(
              image: PdfImage.decode(makeGreyPng(600, 800)),
              words: _lines(<String>['hola mundo']),
              dpi: 150,
            )))
          .build();
    });

    test('starts with a header and ends with EOF', () {
      expect(latin1.decode(bytes.sublist(0, 8)), '%PDF-1.7');
      expect(latin1.decode(bytes.sublist(bytes.length - 6)), '%%EOF\n');
    });

    test('has an xref whose offsets point at their objects', () {
      final text = latin1.decode(bytes, allowInvalid: true);
      final startXref =
          int.parse(RegExp(r'startxref\s+(\d+)').firstMatch(text)!.group(1)!);
      expect(text.substring(startXref, startXref + 4), 'xref');

      final size = int.parse(RegExp(r'/Size (\d+)').firstMatch(text)!.group(1)!);
      final entries = RegExp(r'^(\d{10}) 00000 n $', multiLine: true)
          .allMatches(text.substring(startXref))
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(entries, hasLength(size - 1));
      for (var i = 0; i < entries.length; i++) {
        expect(
          text.startsWith('${i + 1} 0 obj', entries[i]),
          isTrue,
          reason: 'xref entry ${i + 1} points at the wrong byte',
        );
      }
    });

    test('draws the text in render mode 3', () {
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text, contains('3 Tr'));
      expect(text, contains('Tz'));
      expect(text, contains('/WinAnsiEncoding'));
    });

    test('is byte-for-byte reproducible when the date is fixed', () {
      Uint8List build() => (SearchablePdf(
            title: 'Recibo',
            creationDate: DateTime.utc(2026, 9, 8, 12),
          )..addPage(SearchablePage(
                  image: PdfImage.decode(makeGreyPng(600, 800)),
                  words: _lines(<String>['hola mundo']),
                  dpi: 150,
                )))
              .build();
      expect(build(), equals(build()));
    });

    test('refuses to build an empty document', () {
      expect(SearchablePdf().build, throwsStateError);
    });
  });

  group('image embedding', () {
    test('reads PNG geometry without decoding the pixels', () {
      final image = PdfImage.decode(makeGreyPng(123, 45));
      expect(image.width, 123);
      expect(image.height, 45);
      expect(image.colorSpace, '/DeviceGray');
      expect(image.filter, '/FlateDecode');
      expect(image.decodeParms, contains('/Predictor 15'));
      expect(image.decodeParms, contains('/Columns 123'));
    });

    test('rejects what it cannot embed, with a reason', () {
      expect(
        () => PdfImage.decode(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9])),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // The validation §4.5 of the plan calls mandatory. Poppler is the reference
  // implementation for text extraction on Linux; Acrobat and Preview are in
  // UNVERIFIED.md and are not claimed here.
  group('Poppler round-trip', () {
    late Directory dir;

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('searchable_pdf_test');
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    String extract(List<String> lines) {
      final file = File('${dir.path}/page.pdf');
      file.writeAsBytesSync(
        (SearchablePdf(creationDate: DateTime.utc(2026))
              ..addPage(SearchablePage(
                image: PdfImage.decode(makeGreyPng(1240, 1754)),
                words: _lines(lines),
                dpi: 150,
              )))
            .build(),
      );
      final result = Process.runSync(
        'pdftotext',
        <String>['-layout', file.path, '-'],
        stdoutEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      return result.stdout as String;
    }

    test('gives Poppler back the words that went in', () {
      final out = extract(<String>[
        'Factura numero 2026-0042',
        'Importe total 1.234,56 EUR',
      ]);
      for (final word in <String>[
        'Factura',
        'numero',
        '2026-0042',
        'Importe',
        '1.234,56',
      ]) {
        expect(out, contains(word));
      }
    });

    test('keeps accented Spanish text intact through WinAnsi', () {
      final out = extract(<String>['Facturación anual señor ñandú']);
      expect(out, contains('Facturación'));
      expect(out, contains('señor'));
      expect(out, contains('ñandú'));
    });

    test('keeps words on the line they were placed on', () {
      final out = extract(<String>['primera linea aqui', 'segunda linea alli']);
      final lines = const LineSplitter()
          .convert(out)
          .where((l) => l.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(greaterThanOrEqualTo(2)));
      expect(lines[0], contains('primera'));
      expect(lines[0], isNot(contains('segunda')));
      expect(lines[1], contains('segunda'));
    });
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
