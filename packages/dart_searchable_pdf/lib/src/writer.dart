// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'image.dart';
import 'text_layer.dart';

/// Formats a number the way a PDF content stream wants it: plain decimal, no
/// exponent, no trailing zeros.
String pdfNum(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e9) {
    return value.toInt().toString();
  }
  var s = value.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

/// Escapes WinAnsi [codes] into a PDF literal string, brackets included.
///
/// Everything outside printable ASCII goes out as an octal escape, so the file
/// stays 7-bit and no viewer can mistake a byte for a delimiter or a newline.
String pdfLiteralString(List<int> codes) {
  final buffer = StringBuffer('(');
  for (final code in codes) {
    switch (code) {
      case 0x28:
        buffer.write(r'\(');
      case 0x29:
        buffer.write(r'\)');
      case 0x5C:
        buffer.write(r'\\');
      default:
        if (code < 0x20 || code > 0x7E) {
          buffer.write('\\${code.toRadixString(8).padLeft(3, '0')}');
        } else {
          buffer.writeCharCode(code);
        }
    }
  }
  buffer.write(')');
  return buffer.toString();
}

/// Serialises indirect objects and keeps the byte offsets the xref needs.
///
/// TODO: writes a plain cross-reference table, not a cross-reference
/// stream. Object streams and incremental update are what you would add if
/// files ever got large enough for the table to matter; for one image plus one
/// text layer per page it never does.
class PdfWriter {
  PdfWriter() {
    _add('%PDF-1.7\n');
    // A comment with high bytes marks the file as binary for transfer tools.
    _bytes.add(<int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  }

  final BytesBuilder _bytes = BytesBuilder();
  final List<int> _offsets = <int>[0];

  void _add(String s) => _bytes.add(latin1.encode(s));

  /// Reserves the next object number without writing it yet.
  int reserve() {
    _offsets.add(-1);
    return _offsets.length - 1;
  }

  /// Writes object [number] (from [reserve]) with [body] as its content.
  void writeObject(int number, String body) {
    _offsets[number] = _bytes.length;
    _add('$number 0 obj\n$body\nendobj\n');
  }

  /// Writes a stream object: [dictionary] without the `/Length` entry, which
  /// this adds, followed by [data].
  void writeStream(int number, String dictionary, List<int> data) {
    _offsets[number] = _bytes.length;
    _add('$number 0 obj\n');
    _add('<< $dictionary /Length ${data.length} >>\nstream\n');
    _bytes.add(data);
    _add('\nendstream\nendobj\n');
  }

  /// Closes the file with the xref table and trailer.
  Uint8List finish({required int rootObject, required int infoObject}) {
    final startXref = _bytes.length;
    final count = _offsets.length;
    _add('xref\n0 $count\n');
    _add('0000000000 65535 f \n');
    for (var i = 1; i < count; i++) {
      final offset = _offsets[i];
      if (offset < 0) {
        throw StateError('Object $i was reserved but never written.');
      }
      _add('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    _add('trailer\n<< /Size $count /Root $rootObject 0 R '
        '/Info $infoObject 0 R >>\nstartxref\n$startXref\n%%EOF\n');
    return _bytes.takeBytes();
  }
}

/// Body of the image XObject dictionary for [image].
String imageDictionary(PdfImage image) {
  final parms =
      image.decodeParms == null ? '' : '/DecodeParms ${image.decodeParms} ';
  return '/Type /XObject /Subtype /Image '
      '/Width ${image.width} /Height ${image.height} '
      '/ColorSpace ${image.colorSpace} '
      '/BitsPerComponent ${image.bitsPerComponent} '
      '$parms/Filter ${image.filter}';
}

/// Builds the content stream for one page.
///
/// The image is painted first, then the words are drawn on top in text render
/// mode 3 — "fill and stroke nothing" — which is the whole trick: the glyphs
/// take part in selection, search and screen readers without putting a single
/// pixel on the page.
List<int> pageContentStream({
  required double pageWidth,
  required double pageHeight,
  required List<PlacedWord> words,
  required bool debugVisibleText,
}) {
  final buffer = StringBuffer()
    ..write('q\n')
    ..write('${pdfNum(pageWidth)} 0 0 ${pdfNum(pageHeight)} 0 0 cm\n')
    ..write('/Im0 Do\n')
    ..write('Q\n');

  if (words.isNotEmpty) {
    buffer.write('BT\n');
    buffer.write(debugVisibleText ? '0 Tr\n1 0 0 rg\n' : '3 Tr\n');
    for (final word in words) {
      buffer
        ..write('/F0 ${pdfNum(word.fontSize)} Tf\n')
        ..write('${pdfNum(word.horizontalScale)} Tz\n')
        ..write(
            '1 0 0 1 ${pdfNum(word.baselineX)} ${pdfNum(word.baselineY)} Tm\n')
        ..write('${pdfLiteralString(word.codes)} Tj\n');
    }
    buffer.write('ET\n');
  }
  return latin1.encode(buffer.toString());
}

/// Formats a PDF date string, `D:YYYYMMDDHHmmSS+HH'mm'`.
String pdfDate(DateTime when) {
  String two(int n) => n.abs().toString().padLeft(2, '0');
  final utc = when.toUtc();
  return 'D:${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}
