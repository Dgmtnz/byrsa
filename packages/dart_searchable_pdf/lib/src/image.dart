// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A scan page image, ready to be embedded as a PDF image XObject.
///
/// Both supported formats are embedded **without re-encoding**: a JPEG becomes
/// a `/DCTDecode` stream, and a PNG's `IDAT` payload becomes a `/FlateDecode`
/// stream with a PNG predictor, which is the same compression PDF already
/// speaks. That is why this package needs no compression code and no
/// dependencies — and why a scan never loses a second generation of quality.
@immutable
class PdfImage {
  const PdfImage._({
    required this.data,
    required this.width,
    required this.height,
    required this.bitsPerComponent,
    required this.colorSpace,
    required this.filter,
    this.decodeParms,
  });

  /// Raw file bytes, already in a PDF-compatible encoding.
  final Uint8List data;
  final int width;
  final int height;
  final int bitsPerComponent;

  /// `/DeviceRGB` or `/DeviceGray`.
  final String colorSpace;

  /// `/DCTDecode` or `/FlateDecode`.
  final String filter;

  /// Inline dictionary for `/DecodeParms`, or null.
  final String? decodeParms;

  /// Detects JPEG or PNG from the magic bytes and parses the header.
  ///
  /// Throws [UnsupportedError] with a specific reason for anything it cannot
  /// embed losslessly, rather than silently producing a broken page.
  factory PdfImage.decode(Uint8List bytes) {
    if (bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return PdfImage.jpeg(bytes);
    }
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return PdfImage.png(bytes);
    }
    throw UnsupportedError(
      'Not a JPEG or a PNG. Convert to one of those before embedding: '
      'this package embeds without re-encoding and has no image codec.',
    );
  }

  /// Embeds a baseline or progressive JPEG as a `/DCTDecode` stream.
  factory PdfImage.jpeg(Uint8List bytes) {
    var offset = 2; // skip SOI
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] != 0xFF) {
        throw UnsupportedError('Malformed JPEG: expected a marker at $offset.');
      }
      final marker = bytes[offset + 1];
      // Standalone markers carry no length.
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      // SOF0..SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
      final isStartOfFrame =
          marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isStartOfFrame) {
        final precision = bytes[offset + 4];
        final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        final components = bytes[offset + 9];
        if (precision != 8) {
          throw UnsupportedError('JPEG sample precision $precision is not 8.');
        }
        return PdfImage._(
          data: bytes,
          width: width,
          height: height,
          bitsPerComponent: 8,
          colorSpace: switch (components) {
            1 => '/DeviceGray',
            3 => '/DeviceRGB',
            // TODO: CMYK JPEGs also need /Decode [1 0 1 0 1 0 1 0] for the
            // Adobe inverted variant; add when a scanner actually produces one.
            _ => throw UnsupportedError('JPEG with $components components.'),
          },
          filter: '/DCTDecode',
        );
      }
      offset += 2 + length;
    }
    throw UnsupportedError('JPEG has no start-of-frame marker.');
  }

  /// Embeds a PNG by passing its `IDAT` payload through as `/FlateDecode`.
  ///
  /// PNG's compressed data *is* a zlib stream with a per-row predictor, which
  /// is exactly `/FlateDecode` with `/Predictor 15`. No decoding happens here.
  factory PdfImage.png(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 8; // skip signature
    int? width;
    int? height;
    var bitDepth = 8;
    var colorType = 0;
    final idat = BytesBuilder(copy: false);

    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(offset);
      final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
      final body = offset + 8;
      switch (type) {
        case 'IHDR':
          width = data.getUint32(body);
          height = data.getUint32(body + 4);
          bitDepth = bytes[body + 8];
          colorType = bytes[body + 9];
          if (bytes[body + 10] != 0) {
            throw UnsupportedError('PNG compression method is not deflate.');
          }
          if (bytes[body + 12] != 0) {
            throw UnsupportedError(
              'Interlaced PNG. Re-save without Adam7 interlacing: PDF has no '
              'equivalent and this package does not re-encode.',
            );
          }
        case 'IDAT':
          idat.add(Uint8List.sublistView(bytes, body, body + length));
        case 'IEND':
          offset = bytes.length;
          continue;
      }
      offset = body + length + 4; // + CRC
    }

    if (width == null || height == null) {
      throw UnsupportedError('PNG has no IHDR chunk.');
    }
    final colors = switch (colorType) {
      0 => 1,
      2 => 3,
      3 => throw UnsupportedError(
          'Palette PNG. Convert to RGB or grayscale first.'),
      4 || 6 => throw UnsupportedError(
          'PNG with an alpha channel. A scan page is opaque; flatten it first.'),
      _ => throw UnsupportedError('Unknown PNG colour type $colorType.'),
    };
    if (bitDepth != 8 && bitDepth != 16) {
      throw UnsupportedError('PNG bit depth $bitDepth. Use 8 or 16.');
    }

    return PdfImage._(
      data: idat.takeBytes(),
      width: width,
      height: height,
      bitsPerComponent: bitDepth,
      colorSpace: colors == 1 ? '/DeviceGray' : '/DeviceRGB',
      filter: '/FlateDecode',
      decodeParms: '<< /Predictor 15 /Colors $colors '
          '/BitsPerComponent $bitDepth /Columns $width >>',
    );
  }
}
