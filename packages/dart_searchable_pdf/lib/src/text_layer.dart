// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

import 'font_metrics.dart';
import 'geometry.dart';

/// The byte substituted for a character WinAnsiEncoding cannot represent.
const int kUnencodableByte = 0x3F; // '?'

/// Encodes [text] into WinAnsi bytes.
///
/// Characters outside the encoding become `?` — one byte per character, so the
/// word keeps its length and the box keeps its alignment — and are reported
/// through [onWarning] rather than swallowed. WinAnsi covers the six languages
/// milestone M5 targets; scripts beyond it need an embedded TrueType font,
/// which is out of scope (DECISIONS.md D-009).
List<int> encodeWinAnsi(String text, {void Function(String)? onWarning}) {
  final out = <int>[];
  for (final rune in text.runes) {
    final code = winAnsiFromRune(rune);
    if (code == null || helveticaWidths[code] == 0) {
      onWarning?.call(
        'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} is not in '
        'WinAnsiEncoding; substituted "?" in the invisible layer.',
      );
      out.add(kUnencodableByte);
    } else {
      out.add(code);
    }
  }
  return out;
}

/// A word resolved to concrete PDF text-space numbers.
@immutable
class PlacedWord {
  const PlacedWord({
    required this.codes,
    required this.fontSize,
    required this.horizontalScale,
    required this.baselineX,
    required this.baselineY,
  });

  /// WinAnsi bytes of the word.
  final List<int> codes;

  /// Size in points, chosen so the font's ascender-to-descender span matches
  /// the height of the OCR box. That span is what a viewer uses to size a
  /// selection rectangle, so matching it is what makes selection line up.
  final double fontSize;

  /// `Tz` operand, in percent. 100 means the word already happened to be
  /// exactly as wide as its box.
  final double horizontalScale;

  final double baselineX;
  final double baselineY;
}

/// Smallest and largest `Tz` we will emit.
///
/// The bounds are deliberately wide: a single narrow letter alone in a wide box
/// legitimately needs several hundred percent, and refusing to draw it would
/// lose a real word. What the clamp catches is the degenerate case — a box so
/// far from its text that the box itself is wrong — where honouring it would
/// put a meaningless number in the content stream.
const double kMinHorizontalScale = 1;
const double kMaxHorizontalScale = 10000;

/// Places one word, converting from image pixels (y down) to PDF points (y up).
///
/// Returns null for words that cannot be placed: empty text, empty box, or a
/// box the font cannot fill at any scale.
PlacedWord? placeWord(
  PdfWord word, {
  required double pointsPerPixel,
  required int imageHeightPx,
  void Function(String)? onWarning,
}) {
  if (word.text.trim().isEmpty || word.box.isEmpty) return null;

  final codes = encodeWinAnsi(word.text, onWarning: onWarning);
  if (codes.isEmpty) return null;

  var advance = 0;
  for (final code in codes) {
    advance += helveticaWidths[code];
  }
  if (advance == 0) return null;

  final boxWidth = word.box.width * pointsPerPixel;
  final boxHeight = word.box.height * pointsPerPixel;

  final fontSize = boxHeight * 1000 / helveticaSpan;
  final naturalWidth = advance / 1000 * fontSize;
  var scale = 100 * boxWidth / naturalWidth;
  if (scale < kMinHorizontalScale || scale > kMaxHorizontalScale) {
    onWarning?.call(
      'Word "${word.text}" needs Tz ${scale.toStringAsFixed(1)}% to fill its '
      'box; clamped. The OCR box is probably wrong.',
    );
    scale = scale.clamp(kMinHorizontalScale, kMaxHorizontalScale);
  }

  // PDF origin is bottom-left; OCR boxes are top-left. The baseline sits one
  // descender above the bottom edge of the box.
  final bottomFromTop = word.box.bottom;
  final baselineY = (imageHeightPx - bottomFromTop) * pointsPerPixel +
      (-helveticaDescender / 1000) * fontSize;

  return PlacedWord(
    codes: codes,
    fontSize: fontSize,
    horizontalScale: scale,
    baselineX: word.box.left * pointsPerPixel,
    baselineY: baselineY,
  );
}
