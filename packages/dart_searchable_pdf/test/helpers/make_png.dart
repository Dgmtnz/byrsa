// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

/// Builds a solid grey 8-bit PNG in memory.
///
/// Tests generate their fixtures instead of committing them: the repository
/// keeps no binaries, which is both an F-Droid requirement and a nice property
/// when the fixture is three lines of code.
Uint8List makeGreyPng(int width, int height, {int value = 0xF0}) {
  final raw = Uint8List((width + 1) * height);
  for (var y = 0; y < height; y++) {
    final row = y * (width + 1);
    raw[row] = 0; // filter type: none
    raw.fillRange(row + 1, row + 1 + width, value);
  }

  final out = BytesBuilder()
    ..add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = BytesBuilder();
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height);
  ihdr.add(header.buffer.asUint8List(0, 8));
  ihdr.add(<int>[8, 0, 0, 0, 0]); // bit depth, greyscale, deflate, adaptive, no interlace
  out.add(_chunk('IHDR', ihdr.takeBytes()));
  out.add(_chunk('IDAT', Uint8List.fromList(ZLibEncoder().convert(raw))));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String type, Uint8List body) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final out = BytesBuilder();
  out.add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List());
  out.add(typeBytes);
  out.add(body);
  final crc = _crc32(Uint8List.fromList(<int>[...typeBytes, ...body]));
  out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  return out.takeBytes();
}

final List<int> _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
