// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// An axis-aligned rectangle in **image pixel coordinates**: origin top-left,
/// y growing downwards, which is what every OCR engine returns.
///
/// Deliberately not `dart:ui`'s `Rect`: this package is pure Dart so that it
/// can run in a server, a CLI or a test without Flutter.
@immutable
class PdfRect {
  const PdfRect(this.left, this.top, this.right, this.bottom);

  const PdfRect.fromLTWH(this.left, this.top, double width, double height)
      : right = left + width,
        bottom = top + height;

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  String toString() => 'PdfRect($left, $top, $right, $bottom)';

  @override
  bool operator ==(Object other) =>
      other is PdfRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// One recognised word and the box the OCR engine put it in.
///
/// A word is the granularity the invisible layer works at: see DECISIONS.md
/// D-010 for why not lines and not characters.
@immutable
class PdfWord {
  const PdfWord(this.text, this.box);

  final String text;

  /// Bounding box in image pixel coordinates.
  final PdfRect box;

  @override
  String toString() => 'PdfWord("$text", $box)';
}
