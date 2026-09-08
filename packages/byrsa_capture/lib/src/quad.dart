// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A point in **normalised image coordinates**: 0..1 across the frame, origin
/// top-left.
///
/// Normalised on purpose. The detector runs on a downscaled frame, the preview
/// is a different size again, and the captured still is bigger than both.
/// Passing pixels across that boundary is how corners end up in the wrong place.
@immutable
class CapturePoint {
  const CapturePoint(this.x, this.y);

  final double x;
  final double y;

  CapturePoint operator +(CapturePoint other) =>
      CapturePoint(x + other.x, y + other.y);
  CapturePoint operator -(CapturePoint other) =>
      CapturePoint(x - other.x, y - other.y);
  CapturePoint operator *(double factor) => CapturePoint(x * factor, y * factor);

  double distanceTo(CapturePoint other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));

  Map<String, double> toJson() => <String, double>{'x': x, 'y': y};

  static CapturePoint fromJson(Map<Object?, Object?> json) => CapturePoint(
        (json['x']! as num).toDouble(),
        (json['y']! as num).toDouble(),
      );

  @override
  String toString() => '(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      other is CapturePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// The four corners of a detected page, always in the order
/// top-left, top-right, bottom-right, bottom-left.
///
/// The ordering is enforced by [CaptureQuad.fromPoints]. Every consumer — the
/// overlay, the warp, the corner editor — relies on it, and a detector that
/// returns corners in an arbitrary order is the usual source of pages that come
/// out mirrored or rotated by 90°.
@immutable
class CaptureQuad {
  const CaptureQuad(
    this.topLeft,
    this.topRight,
    this.bottomRight,
    this.bottomLeft,
  );

  /// Orders four arbitrary corners into the canonical rotation.
  ///
  /// Sorting by angle around the centroid is what survives perspective: sorting
  /// by "smallest x plus y" breaks as soon as the page is rotated more than
  /// about 45°, which happens constantly when a page is photographed sideways.
  factory CaptureQuad.fromPoints(List<CapturePoint> points) {
    if (points.length != 4) {
      throw ArgumentError('A quad needs exactly four points, got ${points.length}.');
    }
    final cx = points.map((p) => p.x).reduce((a, b) => a + b) / 4;
    final cy = points.map((p) => p.y).reduce((a, b) => a + b) / 4;
    final sorted = points.toList()
      ..sort((a, b) => math
          .atan2(a.y - cy, a.x - cx)
          .compareTo(math.atan2(b.y - cy, b.x - cx)));
    // atan2 is -pi at the left and grows clockwise in a y-down frame, so the
    // sorted list starts somewhere on the upper edge and runs clockwise.
    // Rotate it so the first point is the one closest to the top-left corner.
    var start = 0;
    var best = double.infinity;
    for (var i = 0; i < 4; i++) {
      final d = sorted[i].x + sorted[i].y;
      if (d < best) {
        best = d;
        start = i;
      }
    }
    final ordered = <CapturePoint>[
      for (var i = 0; i < 4; i++) sorted[(start + i) % 4],
    ];
    return CaptureQuad(ordered[0], ordered[1], ordered[2], ordered[3]);
  }

  static CaptureQuad fromJson(List<Object?> json) => CaptureQuad.fromPoints(
        json
            .cast<Map<Object?, Object?>>()
            .map(CapturePoint.fromJson)
            .toList(),
      );

  /// The whole frame — what the UI falls back to when nothing is detected.
  static const CaptureQuad full = CaptureQuad(
    CapturePoint(0, 0),
    CapturePoint(1, 0),
    CapturePoint(1, 1),
    CapturePoint(0, 1),
  );

  final CapturePoint topLeft;
  final CapturePoint topRight;
  final CapturePoint bottomRight;
  final CapturePoint bottomLeft;

  List<CapturePoint> get corners =>
      <CapturePoint>[topLeft, topRight, bottomRight, bottomLeft];

  List<Map<String, double>> toJson() =>
      corners.map((c) => c.toJson()).toList(growable: false);

  /// Shoelace area, as a fraction of the frame.
  double get area {
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// Whether all four interior angles turn the same way.
  ///
  /// A self-intersecting or reflex quad is a detection failure, not a page, and
  /// warping one produces a folded image.
  bool get isConvex {
    var positive = false;
    var negative = false;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final c = corners[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross > 0) positive = true;
      if (cross < 0) negative = true;
      if (positive && negative) return false;
    }
    return true;
  }

  CapturePoint get centroid => CapturePoint(
        corners.map((p) => p.x).reduce((a, b) => a + b) / 4,
        corners.map((p) => p.y).reduce((a, b) => a + b) / 4,
      );

  /// Mean distance between corresponding corners of this quad and [other].
  double meanCornerDistance(CaptureQuad other) {
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      total += corners[i].distanceTo(other.corners[i]);
    }
    return total / 4;
  }

  /// Moves one corner, keeping the ordering contract intact.
  CaptureQuad withCorner(int index, CapturePoint point) {
    final updated = corners.toList()..[index] = point;
    return CaptureQuad(updated[0], updated[1], updated[2], updated[3]);
  }

  CaptureQuad lerpTo(CaptureQuad other, double t) => CaptureQuad(
        topLeft + (other.topLeft - topLeft) * t,
        topRight + (other.topRight - topRight) * t,
        bottomRight + (other.bottomRight - bottomRight) * t,
        bottomLeft + (other.bottomLeft - bottomLeft) * t,
      );

  /// The two vectors Zhang's rectification derives the geometry from.
  ///
  /// Returns null when the corners are degenerate. `n2` carries the page's
  /// horizontal direction and `n3` its vertical one, both in a frame centred on
  /// the image and scaled so that one unit is one frame height.
  ({List<double> n2, List<double> n3})? _rectificationVectors(
      double frameAspectRatio) {
    List<double> h(CapturePoint p) =>
        <double>[(p.x - 0.5) * frameAspectRatio, p.y - 0.5, 1];

    final m1 = h(topLeft);
    final m2 = h(topRight);
    final m3 = h(bottomLeft);
    final m4 = h(bottomRight);

    List<double> cross(List<double> a, List<double> b) => <double>[
          a[1] * b[2] - a[2] * b[1],
          a[2] * b[0] - a[0] * b[2],
          a[0] * b[1] - a[1] * b[0],
        ];
    double dot(List<double> a, List<double> b) =>
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

    final k2Denominator = dot(cross(m2, m4), m3);
    final k3Denominator = dot(cross(m3, m4), m2);
    if (k2Denominator.abs() < 1e-12 || k3Denominator.abs() < 1e-12) return null;

    final k2 = dot(cross(m1, m4), m3) / k2Denominator;
    final k3 = dot(cross(m1, m4), m2) / k3Denominator;

    return (
      n2: <double>[for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]],
      n3: <double>[for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]],
    );
  }

  /// Recovers the camera's focal length from the projected corners, in units of
  /// one frame height.
  ///
  /// Null when the geometry does not determine it — see
  /// [projectiveAspectRatio].
  double? recoverFocalLength({double frameAspectRatio = 1}) {
    final vectors = _rectificationVectors(frameAspectRatio);
    if (vectors == null) return null;
    final (:n2, :n3) = vectors;
    if ((n2[2] * n3[2]).abs() < 1e-9) return null;
    final focalSquared = -(n2[0] * n3[0] + n2[1] * n3[1]) / (n2[2] * n3[2]);
    if (focalSquared <= 0) return null;
    return math.sqrt(focalSquared);
  }

  /// Width-to-height ratio of the physical page, given a known [focalLength]
  /// in units of one frame height.
  double? aspectRatioWithFocal(double focalLength, {double frameAspectRatio = 1}) {
    final vectors = _rectificationVectors(frameAspectRatio);
    if (vectors == null || focalLength <= 0) return null;
    final (:n2, :n3) = vectors;
    final f2 = focalLength * focalLength;
    final widthTerm = (n2[0] * n2[0] + n2[1] * n2[1]) / f2 + n2[2] * n2[2];
    final heightTerm = (n3[0] * n3[0] + n3[1] * n3[1]) / f2 + n3[2] * n3[2];
    if (widthTerm <= 0 || heightTerm <= 0) return null;
    return math.sqrt(widthTerm / heightTerm);
  }

  /// Recovers the width-to-height ratio of the physical page.
  ///
  /// A page photographed at an angle is a projection, so the ratio of the sides
  /// you can see is not the ratio of the paper. Averaging the visible sides
  /// makes an A4 sheet shot from 30° come out visibly squashed. This is the
  /// closed-form solution from Zhang and He's whiteboard-rectification work: it
  /// recovers the camera's focal length from the projected corners, and the
  /// true ratio with it, assuming a pinhole camera whose principal point is the
  /// centre of the frame.
  ///
  /// [frameAspectRatio] is the width/height of the frame the corners are
  /// normalised against, needed to undo the normalisation before the projective
  /// maths.
  ///
  /// Returns null when the geometry does not determine the answer. That is not
  /// an edge case to shrug at: it happens for **every shot tilted about a
  /// single axis**, where one pair of edges stays parallel in the image, and
  /// there is then genuinely a one-parameter family of pages that project to
  /// the same trapezoid. [aspectRatioOrFallback] resolves it with an assumed
  /// focal length.
  double? projectiveAspectRatio({double frameAspectRatio = 1}) {
    final focal = recoverFocalLength(frameAspectRatio: frameAspectRatio);
    if (focal == null) return null;
    return aspectRatioWithFocal(focal, frameAspectRatio: frameAspectRatio);
  }

  /// Typical focal length of a phone's main camera, in frame heights.
  ///
  /// A calibration constant, not a law: it corresponds to roughly a 65°
  /// horizontal field of view on a 4:3 sensor. Cameras vary, and a caller that
  /// knows the real value from the platform should pass it. This is the knob
  /// you turn when rectified pages come out consistently too wide or too tall
  /// on a particular device.
  static const double typicalPhoneFocalLength = 1.0;

  /// Best available width-to-height ratio for the page.
  ///
  /// Tries the closed form, then an assumed focal length for the single-axis
  /// tilt case, then — for a head-on shot, where there is no perspective left
  /// to undo — the mean of the visible sides.
  double aspectRatioOrFallback({
    double frameAspectRatio = 1,
    double assumedFocalLength = typicalPhoneFocalLength,
  }) {
    final projective = projectiveAspectRatio(frameAspectRatio: frameAspectRatio);
    if (projective != null && projective.isFinite && projective > 0) {
      return projective;
    }
    final assumed =
        aspectRatioWithFocal(assumedFocalLength, frameAspectRatio: frameAspectRatio);
    if (assumed != null && assumed.isFinite && assumed > 0) return assumed;

    double side(CapturePoint a, CapturePoint b) => math.sqrt(
        math.pow((a.x - b.x) * frameAspectRatio, 2) + math.pow(a.y - b.y, 2));
    final width = (side(topLeft, topRight) + side(bottomLeft, bottomRight)) / 2;
    final height = (side(topLeft, bottomLeft) + side(topRight, bottomRight)) / 2;
    return height <= 0 ? 1 : width / height;
  }

  @override
  String toString() => 'CaptureQuad(${corners.join(", ")})';

  @override
  bool operator ==(Object other) =>
      other is CaptureQuad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode =>
      Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
