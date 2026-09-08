// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter_test/flutter_test.dart';

/// Projects a rectangle of [width] x [height] through a pinhole camera and
/// returns its corners in normalised frame coordinates.
///
/// This is the whole point of the aspect-ratio test: we know what the paper
/// measures, we know nothing else, and the code has to get the ratio back.
CaptureQuad project({
  required double width,
  required double height,
  required double tiltX,
  required double tiltY,
  double focal = 900,
  double distance = 1000,
  int frameWidth = 1280,
  int frameHeight = 960,
}) {
  final cosX = math.cos(tiltX), sinX = math.sin(tiltX);
  final cosY = math.cos(tiltY), sinY = math.sin(tiltY);

  CapturePoint corner(double u, double v) {
    // Page plane -> world, rotating about x then y.
    var x = u, y = v, z = 0.0;
    final y1 = y * cosX - z * sinX;
    final z1 = y * sinX + z * cosX;
    y = y1;
    z = z1;
    final x1 = x * cosY + z * sinY;
    z = -x * sinY + z * cosY;
    x = x1;
    z += distance;

    return CapturePoint(
      (focal * x / z) / frameWidth + 0.5,
      (focal * y / z) / frameHeight + 0.5,
    );
  }

  final w = width / 2, h = height / 2;
  return CaptureQuad(
    corner(-w, -h),
    corner(w, -h),
    corner(w, h),
    corner(-w, h),
  );
}

void main() {
  group('corner ordering', () {
    test(
        'puts arbitrary corners into top-left, top-right, bottom-right, bottom-left',
        () {
      const points = <CapturePoint>[
        CapturePoint(0.8, 0.9),
        CapturePoint(0.2, 0.1),
        CapturePoint(0.2, 0.9),
        CapturePoint(0.8, 0.1),
      ];
      final quad = CaptureQuad.fromPoints(points);
      expect(quad.topLeft, const CapturePoint(0.2, 0.1));
      expect(quad.topRight, const CapturePoint(0.8, 0.1));
      expect(quad.bottomRight, const CapturePoint(0.8, 0.9));
      expect(quad.bottomLeft, const CapturePoint(0.2, 0.9));
    });

    test('survives a page rotated past 45°, where naive x+y sorting breaks',
        () {
      // A diamond: no corner is simultaneously leftmost and topmost.
      const points = <CapturePoint>[
        CapturePoint(0.5, 0.1),
        CapturePoint(0.9, 0.5),
        CapturePoint(0.5, 0.9),
        CapturePoint(0.1, 0.5),
      ];
      final quad = CaptureQuad.fromPoints(points);
      expect(quad.isConvex, isTrue);
      // Going round the quad must not cross itself: consecutive corners are
      // adjacent, so opposite corners are the far ones.
      expect(quad.topLeft.distanceTo(quad.bottomRight),
          greaterThan(quad.topLeft.distanceTo(quad.topRight)));
    });

    test('rejects anything that is not four points', () {
      expect(() => CaptureQuad.fromPoints(const <CapturePoint>[]),
          throwsArgumentError);
    });
  });

  group('geometry', () {
    test('measures area as a fraction of the frame', () {
      expect(CaptureQuad.full.area, 1);
      expect(
        const CaptureQuad(
          CapturePoint(0.25, 0.25),
          CapturePoint(0.75, 0.25),
          CapturePoint(0.75, 0.75),
          CapturePoint(0.25, 0.75),
        ).area,
        closeTo(0.25, 1e-12),
      );
    });

    test('spots a bow-tie quad, which would warp to a folded page', () {
      expect(CaptureQuad.full.isConvex, isTrue);
      expect(
        const CaptureQuad(
          CapturePoint(0, 0),
          CapturePoint(1, 0),
          CapturePoint(0, 1),
          CapturePoint(1, 1),
        ).isConvex,
        isFalse,
      );
    });
  });

  group('projective aspect ratio', () {
    const a4 = 210 / 297;

    test('is honest that a single-axis tilt does not determine the answer', () {
      // Tilted about x only: the top and bottom edges stay parallel in the
      // image, so a whole family of pages projects to the same trapezoid.
      // Returning a confident wrong number here is how scanners produce
      // subtly squashed A4.
      final quad = project(width: 210, height: 297, tiltX: 0.52, tiltY: 0);
      expect(quad.projectiveAspectRatio(frameAspectRatio: 1280 / 960), isNull);
      expect(quad.recoverFocalLength(frameAspectRatio: 1280 / 960), isNull);
    });

    test('resolves the single-axis case once a focal length is supplied', () {
      final quad = project(width: 210, height: 297, tiltX: 0.52, tiltY: 0);
      expect(
        // The synthetic camera used f = 900px on a 960px-tall frame.
        quad.aspectRatioWithFocal(900 / 960, frameAspectRatio: 1280 / 960),
        closeTo(a4, 0.01),
      );
    });

    test('gets within 10% of A4 from the assumed phone focal length alone', () {
      final quad = project(width: 210, height: 297, tiltX: 0.52, tiltY: 0);
      expect(
        quad.aspectRatioOrFallback(frameAspectRatio: 1280 / 960),
        closeTo(a4, a4 * 0.1),
      );
    });

    test('recovers the camera focal length it was shot with', () {
      final quad = project(width: 210, height: 297, tiltX: 0.35, tiltY: 0.45);
      expect(
        quad.recoverFocalLength(frameAspectRatio: 1280 / 960),
        closeTo(900 / 960, 0.02),
      );
    });

    test('recovers A4 under tilt on both axes at once', () {
      final quad = project(width: 210, height: 297, tiltX: 0.35, tiltY: 0.45);
      expect(
        quad.projectiveAspectRatio(frameAspectRatio: 1280 / 960),
        closeTo(a4, 0.01),
      );
    });

    test('beats averaging the visible sides, which is what it is for', () {
      final quad = project(width: 210, height: 297, tiltX: 0.6, tiltY: 0.3);
      const frame = 1280 / 960;

      double side(CapturePoint a, CapturePoint b) =>
          math.sqrt(math.pow((a.x - b.x) * frame, 2) + math.pow(a.y - b.y, 2));
      final naive = ((side(quad.topLeft, quad.topRight) +
                  side(quad.bottomLeft, quad.bottomRight)) /
              2) /
          ((side(quad.topLeft, quad.bottomLeft) +
                  side(quad.topRight, quad.bottomRight)) /
              2);

      final projective = quad.projectiveAspectRatio(frameAspectRatio: frame)!;
      expect((projective - a4).abs(), lessThan((naive - a4).abs()));
    });

    test('recovers a landscape receipt too, not just portrait pages', () {
      final quad = project(width: 300, height: 100, tiltX: 0.4, tiltY: 0.2);
      expect(
        quad.projectiveAspectRatio(frameAspectRatio: 1280 / 960),
        closeTo(3, 0.05),
      );
    });

    test('falls back to the visible ratio for a head-on shot', () {
      // No perspective to undo: the closed form is degenerate and the visible
      // ratio is already right.
      final quad = project(width: 200, height: 100, tiltX: 0, tiltY: 0);
      expect(
        quad.aspectRatioOrFallback(frameAspectRatio: 1280 / 960),
        closeTo(2, 0.02),
      );
    });
  });
}
