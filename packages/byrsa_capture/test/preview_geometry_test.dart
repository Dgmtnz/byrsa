// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arithmetic behind the first bug a human found on a real device.
///
/// The preview was stretched and the detected outline looked mirrored. Neither
/// was a detection fault: the texture was drawn in sensor space while the
/// corners were already reported in display space, and nothing applied the
/// camera's aspect ratio. These assertions are that arithmetic, so the fix
/// cannot quietly regress into a wrong-shaped preview again.
void main() {
  group('preview geometry', () {
    test('a quarter turn swaps the axes, which is the whole distortion', () {
      // The common case: a 16:9 sensor held upright on a portrait phone.
      const landscapeSensor = CapturePreviewGeometry(
        width: 1920,
        height: 1080,
        rotationDegrees: 90,
      );

      expect(landscapeSensor.quarterTurns, 1);
      expect(landscapeSensor.displayAspectRatio, closeTo(1080 / 1920, 1e-9));
      // Not the buffer's own ratio — that is exactly what looked squashed.
      expect(landscapeSensor.displayAspectRatio,
          isNot(closeTo(1920 / 1080, 1e-9)));
    });

    test('half a turn keeps the shape, because the axes do not move', () {
      const upsideDown = CapturePreviewGeometry(
        width: 1920,
        height: 1080,
        rotationDegrees: 180,
      );
      expect(upsideDown.quarterTurns, 2);
      expect(upsideDown.displayAspectRatio, closeTo(1920 / 1080, 1e-9));
    });

    test('three quarters swaps them back', () {
      const geometry = CapturePreviewGeometry(
        width: 1920,
        height: 1080,
        rotationDegrees: 270,
      );
      expect(geometry.quarterTurns, 3);
      expect(geometry.displayAspectRatio, closeTo(1080 / 1920, 1e-9));
    });

    test('an unrotated buffer is left exactly as it is', () {
      const geometry = CapturePreviewGeometry(
        width: 1280,
        height: 720,
        rotationDegrees: 0,
      );
      expect(geometry.quarterTurns, 0);
      expect(geometry.displayAspectRatio, closeTo(1280 / 720, 1e-9));
    });

    test('a degenerate buffer reports a square rather than dividing by zero',
        () {
      const geometry =
          CapturePreviewGeometry(width: 0, height: 0, rotationDegrees: 90);
      expect(geometry.displayAspectRatio, 1);
    });

    test('a full turn is no turn', () {
      const geometry =
          CapturePreviewGeometry(width: 800, height: 600, rotationDegrees: 360);
      expect(geometry.quarterTurns, 0);
      expect(geometry.displayAspectRatio, closeTo(800 / 600, 1e-9));
    });
  });
}
