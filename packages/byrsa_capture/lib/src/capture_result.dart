// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

import 'quad.dart';

/// Why the capture UI is not ready to take a picture yet.
///
/// The point of naming these is that the interface can say *what to do* —
/// "move closer", "hold still" — instead of a generic "no document found",
/// which is the single most common complaint about scanner apps.
enum CaptureHint {
  /// No plausible page in the frame.
  noDocument,

  /// A page is there but too small: too far away, or too zoomed out.
  tooFar,

  /// The page runs off the edge of the frame.
  cropped,

  /// The camera or the page is still moving.
  moving,

  /// The frame is out of focus or motion-blurred.
  blurry,

  /// Not enough light for a usable scan.
  tooDark,

  /// Everything is in order.
  ready,
}

/// One live detection, as the preview receives them.
@immutable
class CaptureDetection {
  const CaptureDetection({
    required this.quad,
    required this.hint,
    required this.sharpness,
    required this.brightness,
    required this.stableFor,
  });

  /// Null when nothing was detected this frame.
  final CaptureQuad? quad;

  final CaptureHint hint;

  /// Relative focus measure, 0..1. Higher is sharper. Comparable only between
  /// frames of the same scene, which is all auto-capture needs.
  final double sharpness;

  /// Mean luma, 0..1.
  final double brightness;

  /// How long the quad has been within the stability threshold.
  final Duration stableFor;

  bool get isReady => hint == CaptureHint.ready;
}

/// A captured page.
@immutable
class CapturedPage {
  const CapturedPage({
    required this.originalPath,
    required this.quad,
    this.rectifiedPath,
    this.width,
    this.height,
  });

  /// The full-resolution frame, untouched.
  ///
  /// Always kept: the corners can be corrected afterwards, and re-warping from
  /// the original is lossless where re-warping a warp is not.
  final String originalPath;

  /// The perspective-corrected page, if the warp has run.
  final String? rectifiedPath;

  /// Corners used for the warp, in the original frame's normalised coordinates.
  final CaptureQuad quad;

  final int? width;
  final int? height;

  CapturedPage copyWith({String? rectifiedPath, CaptureQuad? quad}) =>
      CapturedPage(
        originalPath: originalPath,
        rectifiedPath: rectifiedPath ?? this.rectifiedPath,
        quad: quad ?? this.quad,
        width: width,
        height: height,
      );

  static CapturedPage fromJson(Map<Object?, Object?> json) => CapturedPage(
        originalPath: json['originalPath']! as String,
        rectifiedPath: json['rectifiedPath'] as String?,
        quad: CaptureQuad.fromJson(json['quad']! as List<Object?>),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
      );
}
