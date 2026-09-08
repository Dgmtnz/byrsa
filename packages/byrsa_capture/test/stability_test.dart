// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter_test/flutter_test.dart';

CaptureQuad centred(double size, {double dx = 0, double dy = 0}) {
  final half = size / 2;
  return CaptureQuad(
    CapturePoint(0.5 - half + dx, 0.5 - half + dy),
    CapturePoint(0.5 + half + dx, 0.5 - half + dy),
    CapturePoint(0.5 + half + dx, 0.5 + half + dy),
    CapturePoint(0.5 - half + dx, 0.5 + half + dy),
  );
}

void main() {
  group('QuadSmoother', () {
    test('follows a small movement gradually', () {
      final smoother = QuadSmoother(smoothing: 0.5);
      final start = centred(0.5);
      final moved = centred(0.5, dx: 0.02);

      smoother.add(start);
      final result = smoother.add(moved)!;
      expect(result.topLeft.x,
          closeTo((start.topLeft.x + moved.topLeft.x) / 2, 1e-12));
    });

    test('jumps rather than sliding when the page really moves', () {
      final smoother = QuadSmoother(jumpThreshold: 0.05);
      smoother.add(centred(0.5));
      final far = centred(0.5, dx: 0.4);
      expect(smoother.add(far), far);
    });

    test('forgets everything when detection is lost', () {
      final smoother = QuadSmoother()..add(centred(0.5));
      expect(smoother.add(null), isNull);
      expect(smoother.current, isNull);
    });
  });

  group('StabilityTracker', () {
    const frame = Duration(milliseconds: 100);

    CaptureHintResult feed(
      StabilityTracker tracker,
      CaptureQuad? quad, {
      int frames = 1,
      double sharpness = 1,
      double brightness = 1,
    }) {
      late CaptureHintResult result;
      for (var i = 0; i < frames; i++) {
        result = tracker.update(
          quad: quad,
          frameInterval: frame,
          sharpness: sharpness,
          brightness: brightness,
        );
      }
      return result;
    }

    test('says what to do, not that something failed', () {
      final tracker = StabilityTracker();
      expect(feed(tracker, null).hint, CaptureHint.noDocument);
      expect(feed(tracker, centred(0.2), frames: 20).hint, CaptureHint.tooFar);
      expect(feed(tracker, CaptureQuad.full, frames: 20).hint,
          CaptureHint.cropped);
      expect(
        feed(tracker, centred(0.6), frames: 20, brightness: 0.05).hint,
        CaptureHint.tooDark,
      );
    });

    test('does not fire before the scene has held still', () {
      final tracker = StabilityTracker(
        requiredStillness: const Duration(milliseconds: 500),
      );
      expect(feed(tracker, centred(0.6), frames: 3).hint, CaptureHint.moving);
      expect(feed(tracker, centred(0.6), frames: 4).hint, CaptureHint.ready);
    });

    test('refuses to auto-capture a blurred frame', () {
      // The failure that ruins auto-capture: firing on a steady but blurred
      // scene gives the user a photo they have to notice and retake.
      final tracker = StabilityTracker();
      expect(
        feed(tracker, centred(0.6), frames: 20, sharpness: 0.05).hint,
        CaptureHint.blurry,
      );
    });

    test('restarts the clock when the page moves again', () {
      final tracker = StabilityTracker(
        requiredStillness: const Duration(milliseconds: 300),
      );
      feed(tracker, centred(0.6), frames: 5);
      expect(tracker.stableFor.inMilliseconds, greaterThanOrEqualTo(300));
      feed(tracker, centred(0.6, dx: 0.2));
      expect(tracker.stableFor, Duration.zero);
    });

    test('treats a self-intersecting quad as no document at all', () {
      final tracker = StabilityTracker();
      const bowTie = CaptureQuad(
        CapturePoint(0.2, 0.2),
        CapturePoint(0.8, 0.2),
        CapturePoint(0.2, 0.8),
        CapturePoint(0.8, 0.8),
      );
      expect(feed(tracker, bowTie, frames: 20).hint, CaptureHint.noDocument);
    });
  });
}
