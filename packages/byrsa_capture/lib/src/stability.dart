// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'capture_result.dart';
import 'quad.dart';

/// Smooths the detected quad across frames.
///
/// A raw per-frame detection jitters by a few pixels even on a tripod, and an
/// overlay that jitters reads as broken. Exponential smoothing costs nothing;
/// the part that matters is the jump threshold, which lets a genuine move to a
/// different page snap instead of sliding across the screen for half a second.
class QuadSmoother {
  QuadSmoother({this.smoothing = 0.35, this.jumpThreshold = 0.08})
      : assert(smoothing > 0 && smoothing <= 1, 'smoothing is a 0..1 weight');

  /// Weight of each new detection. Lower is smoother and laggier.
  final double smoothing;

  /// Mean corner movement, in normalised units, above which we stop smoothing
  /// and jump straight to the new quad.
  final double jumpThreshold;

  CaptureQuad? _current;

  CaptureQuad? get current => _current;

  CaptureQuad? add(CaptureQuad? detection) {
    if (detection == null) {
      _current = null;
      return null;
    }
    final previous = _current;
    if (previous == null ||
        previous.meanCornerDistance(detection) > jumpThreshold) {
      _current = detection;
    } else {
      _current = previous.lerpTo(detection, smoothing);
    }
    return _current;
  }

  void reset() => _current = null;
}

/// Decides when the scene has held still long enough to capture by itself.
///
/// Auto-capture is the feature that makes a scanner feel good, and the feature
/// that ruins it when it fires early: a blurred shot the user has to notice and
/// redo is worse than one they had to tap for.
class StabilityTracker {
  StabilityTracker({
    this.movementThreshold = 0.012,
    this.requiredStillness = const Duration(milliseconds: 700),
    this.minimumSharpness = 0.25,
    this.minimumBrightness = 0.12,
    this.minimumArea = 0.15,
  });

  /// Mean corner movement between frames, in normalised units, still counted
  /// as "not moving".
  final double movementThreshold;

  /// How long the quad has to stay under [movementThreshold].
  final Duration requiredStillness;

  final double minimumSharpness;
  final double minimumBrightness;

  /// Smallest fraction of the frame a page may occupy. Below this the capture
  /// has too few pixels for OCR to be worth attempting.
  final double minimumArea;

  CaptureQuad? _previous;
  Duration _stableFor = Duration.zero;

  Duration get stableFor => _stableFor;

  /// Feeds one frame and returns what the interface should say about it.
  CaptureHintResult update({
    required CaptureQuad? quad,
    required Duration frameInterval,
    required double sharpness,
    required double brightness,
  }) {
    if (quad == null || !quad.isConvex) {
      _previous = null;
      _stableFor = Duration.zero;
      return CaptureHintResult(CaptureHint.noDocument, _stableFor);
    }

    final previous = _previous;
    _previous = quad;
    if (previous == null ||
        previous.meanCornerDistance(quad) > movementThreshold) {
      _stableFor = Duration.zero;
    } else {
      _stableFor += frameInterval;
    }

    // Order matters: report the problem the user can act on first.
    if (quad.area < minimumArea) {
      return CaptureHintResult(CaptureHint.tooFar, _stableFor);
    }
    if (_touchesEdge(quad)) {
      return CaptureHintResult(CaptureHint.cropped, _stableFor);
    }
    if (brightness < minimumBrightness) {
      return CaptureHintResult(CaptureHint.tooDark, _stableFor);
    }
    if (_stableFor < requiredStillness) {
      return CaptureHintResult(CaptureHint.moving, _stableFor);
    }
    if (sharpness < minimumSharpness) {
      return CaptureHintResult(CaptureHint.blurry, _stableFor);
    }
    return CaptureHintResult(CaptureHint.ready, _stableFor);
  }

  void reset() {
    _previous = null;
    _stableFor = Duration.zero;
  }

  static bool _touchesEdge(CaptureQuad quad, {double margin = 0.005}) =>
      quad.corners.any((c) =>
          c.x <= margin ||
          c.y <= margin ||
          c.x >= 1 - margin ||
          c.y >= 1 - margin);
}

/// Result of one [StabilityTracker.update].
class CaptureHintResult {
  const CaptureHintResult(this.hint, this.stableFor);

  final CaptureHint hint;
  final Duration stableFor;
}
