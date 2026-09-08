// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// Builds a small searchable PDF and, if Poppler is around, reads the text back
// out to prove the layer works:
//
//   dart run example/searchable_pdf_example.dart
//   pdftotext -layout example_out.pdf -

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';

void main(List<String> args) {
  final imagePath = args.isEmpty ? null : args.first;
  final image = imagePath == null
      ? PdfImage.decode(_blankPage(1240, 1754))
      : PdfImage.decode(File(imagePath).readAsBytesSync());

  // Pretend these came out of an OCR engine: text plus a box in image pixels.
  const words = <PdfWord>[
    PdfWord('FACTURA', PdfRect(120, 200, 420, 260)),
    PdfWord('2026-0042', PdfRect(440, 200, 720, 260)),
    PdfWord('Importe', PdfRect(120, 320, 310, 366)),
    PdfWord('total:', PdfRect(322, 320, 452, 366)),
    PdfWord('1.234,56', PdfRect(470, 320, 700, 366)),
    PdfWord('€', PdfRect(712, 320, 744, 366)),
  ];

  final pdf = SearchablePdf(
    title: 'Factura 2026-0042',
    // Set this and the same input always produces the same bytes.
    creationDate: DateTime.utc(2026, 9, 8),
    // Flip to true to see where the invisible words actually landed.
    debugVisibleText: false,
    onWarning: (message) => stderr.writeln('warning: $message'),
  )..addPage(SearchablePage(image: image, words: words, dpi: 150));

  final out = File('example_out.pdf')..writeAsBytesSync(pdf.build());
  stdout.writeln('wrote ${out.path} (${out.lengthSync()} bytes)');

  try {
    final result =
        Process.runSync('pdftotext', <String>['-layout', out.path, '-']);
    stdout.writeln('--- pdftotext says ---\n${result.stdout}');
  } on ProcessException {
    stdout.writeln('install poppler-utils to read the text back out.');
  }
}

/// A blank white PNG, so the example runs with no input file.
Uint8List _blankPage(int width, int height) {
  final raw = <int>[];
  for (var y = 0; y < height; y++) {
    raw.add(0);
    raw.addAll(List<int>.filled(width, 0xFF));
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
    ..._chunk('IHDR', <int>[
      ...(_u32(width)),
      ...(_u32(height)),
      8,
      0,
      0,
      0,
      0,
    ]),
    ..._chunk('IDAT', ZLibEncoder().convert(raw)),
    ..._chunk('IEND', const <int>[]),
  ]);
}

List<int> _u32(int v) =>
    <int>[v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];

List<int> _chunk(String type, List<int> body) {
  final payload = <int>[...type.codeUnits, ...body];
  return <int>[..._u32(body.length), ...payload, ..._u32(_crc32(payload))];
}

final List<int> _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
