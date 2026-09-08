// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'capture_result.dart';
import 'quad.dart';

/// How the camera session should behave.
class CaptureOptions {
  const CaptureOptions({
    this.detectionsPerSecond = 8,
    this.torch = false,
    this.rectifyOnCapture = true,
  });

  /// How often the native side runs detection.
  ///
  /// Detection runs in the platform layer and only the four corners cross into
  /// Dart, which is the whole reason this is affordable. The rate is capped
  /// rather than tied to the preview because it is the detector, not the
  /// preview, that costs battery — see the plan's §4.1.
  final int detectionsPerSecond;

  final bool torch;

  /// Whether the native side warps the still immediately after capture.
  final bool rectifyOnCapture;

  Map<String, Object?> toJson() => <String, Object?>{
        'detectionsPerSecond': detectionsPerSecond,
        'torch': torch,
        'rectifyOnCapture': rectifyOnCapture,
      };
}

/// The contract every platform implementation of `byrsa_capture` satisfies.
///
/// It is identical on Android and iOS on purpose (plan §0.2): the iOS side is
/// written and kept compiling even though nobody in the project can measure it
/// yet, and a symmetric API is what would make a later switch of inference
/// backend an implementation change rather than a redesign.
abstract class ByrsaCapturePlatform extends PlatformInterface {
  ByrsaCapturePlatform() : super(token: _token);

  static final Object _token = Object();
  static ByrsaCapturePlatform? _instance;

  static ByrsaCapturePlatform get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError(
        'No byrsa_capture implementation registered for this platform. '
        'Camera capture needs Android or iOS; on desktop and web, import a '
        'still image instead.',
      );
    }
    return instance;
  }

  static set instance(ByrsaCapturePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Starts the camera and returns the Flutter texture id to display.
  Future<int> start(CaptureOptions options);

  Future<void> stop();

  /// Live detections. One event per analysed frame, corners already in
  /// normalised coordinates.
  Stream<CaptureDetection> get detections;

  /// Takes a full-resolution still.
  Future<CapturedPage> capture();

  /// Warps [imagePath] using [quad] and writes a new file.
  ///
  /// Separate from [capture] so that a corner correction made after the fact
  /// re-warps from the original, rather than warping an already warped image.
  Future<String> rectify({
    required String imagePath,
    required CaptureQuad quad,
    double? targetAspectRatio,
  });

  Future<void> setTorch({required bool on});

  /// Whether this device can run the capture pipeline at all.
  Future<bool> isSupported();
}
