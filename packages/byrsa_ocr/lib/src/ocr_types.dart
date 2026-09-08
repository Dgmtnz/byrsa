// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A box in image pixel coordinates, origin top-left.
///
/// Plain doubles and no `dart:ui`, so the result of an OCR run can be handed
/// straight to a pure-Dart PDF writer, a server, or a test.
@immutable
class OcrBox {
  const OcrBox(this.left, this.top, this.right, this.bottom);

  /// Axis-aligned bounds of an arbitrary polygon — what detectors actually
  /// return, since text on a photographed page is rarely axis-aligned.
  factory OcrBox.ofPolygon(List<({double x, double y})> points) {
    var left = points.first.x, right = left;
    var top = points.first.y, bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    return OcrBox(left, top, right, bottom);
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centreY => (top + bottom) / 2;

  /// How much of this box's height overlaps [other]'s, as a fraction of the
  /// smaller of the two. Used to decide whether two words are on one line.
  double verticalOverlap(OcrBox other) {
    final overlap = math.min(bottom, other.bottom) - math.max(top, other.top);
    final smaller = math.min(height, other.height);
    return smaller <= 0 ? 0 : (overlap / smaller).clamp(0.0, 1.0);
  }

  @override
  String toString() => 'OcrBox($left, $top, $right, $bottom)';

  @override
  bool operator ==(Object other) =>
      other is OcrBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// One recognised word.
@immutable
class OcrWord {
  const OcrWord(
      {required this.text, required this.box, required this.confidence});

  final String text;
  final OcrBox box;

  /// 0..1. Engines disagree about what this means; treat it as a ranking, not
  /// a probability.
  final double confidence;

  @override
  String toString() => '"$text" ${confidence.toStringAsFixed(2)}';
}

/// A run of words the engine considers one line.
@immutable
class OcrLine {
  const OcrLine(this.words);

  final List<OcrWord> words;

  String get text => words.map((w) => w.text).join(' ');

  OcrBox get box => OcrBox.ofPolygon(<({double x, double y})>[
        for (final word in words) ...<({double x, double y})>[
          (x: word.box.left, y: word.box.top),
          (x: word.box.right, y: word.box.bottom),
        ],
      ]);

  double get confidence => words.isEmpty
      ? 0
      : words.map((w) => w.confidence).reduce((a, b) => a + b) / words.length;
}

/// Everything one image produced.
@immutable
class OcrResult {
  const OcrResult({
    required this.lines,
    required this.imageWidth,
    required this.imageHeight,
    required this.engine,
    required this.duration,
  });

  final List<OcrLine> lines;
  final int imageWidth;
  final int imageHeight;

  /// Which implementation produced this — `apple-vision` or `pp-ocr-onnx`.
  ///
  /// Recorded on the result, not just logged, because a number measured with
  /// one engine says nothing about the other and the harness has to be able to
  /// tell them apart.
  final String engine;

  final Duration duration;

  List<OcrWord> get words => <OcrWord>[for (final line in lines) ...line.words];

  /// The whole page as text, in reading order, one line per line.
  String get text => lines.map((l) => l.text).join('\n');

  bool get isEmpty => lines.isEmpty;
}
