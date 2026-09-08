// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'ocr_types.dart';

/// Turns a bag of detected words into lines, in reading order.
///
/// Detectors return boxes in whatever order they came out of the network. A
/// scan that reads correctly on screen and pastes as scrambled text is one of
/// the most common complaints about OCR output, and this is where it is fixed.
///
/// TODO: this groups by vertical overlap and sorts left to right, which is
/// right for a single column of left-to-right text — receipts, invoices,
/// letters, book pages. It does not do column detection, and a two-column
/// journal page will interleave. The upgrade path is XY-cut segmentation; the
/// benchmark decides whether the fifty-document set contains enough multi-column
/// pages to justify it.
class ReadingOrder {
  const ReadingOrder({this.overlapThreshold = 0.5, this.minimumConfidence = 0.0});

  /// Fraction of shared height above which two words are the same line.
  final double overlapThreshold;

  /// Words below this confidence are dropped before grouping.
  final double minimumConfidence;

  List<OcrLine> group(List<OcrWord> words) {
    final kept = words
        .where((w) => w.confidence >= minimumConfidence && w.text.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.box.top.compareTo(b.box.top));

    final lines = <List<OcrWord>>[];
    for (final word in kept) {
      // Compare against the line whose vertical extent overlaps most: taking
      // the first match makes the result depend on detector order.
      List<OcrWord>? best;
      var bestOverlap = overlapThreshold;
      for (final line in lines) {
        final overlap = _lineBox(line).verticalOverlap(word.box);
        if (overlap >= bestOverlap) {
          bestOverlap = overlap;
          best = line;
        }
      }
      if (best == null) {
        lines.add(<OcrWord>[word]);
      } else {
        best.add(word);
      }
    }

    for (final line in lines) {
      line.sort((a, b) => a.box.left.compareTo(b.box.left));
    }
    lines.sort((a, b) => _lineBox(a).centreY.compareTo(_lineBox(b).centreY));
    return lines.map(OcrLine.new).toList(growable: false);
  }

  static OcrBox _lineBox(List<OcrWord> words) {
    var left = words.first.box.left;
    var right = words.first.box.right;
    var top = words.first.box.top;
    var bottom = words.first.box.bottom;
    for (final word in words.skip(1)) {
      if (word.box.left < left) left = word.box.left;
      if (word.box.right > right) right = word.box.right;
      if (word.box.top < top) top = word.box.top;
      if (word.box.bottom > bottom) bottom = word.box.bottom;
    }
    return OcrBox(left, top, right, bottom);
  }
}
