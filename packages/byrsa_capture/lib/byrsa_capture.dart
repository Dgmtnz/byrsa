// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// Live document edge detection and perspective correction for Flutter, with
/// **no dependency on Google Play Services**, so the result can ship on
/// F-Droid and other independent distributions.
///
/// Detection runs in the platform layer — CameraX on Android, AVFoundation and
/// Vision on iOS — and only four corners cross into Dart per frame. That is
/// deliberate: streaming camera frames into Dart is where a scanner's battery
/// and thermal budget goes.
library;

import 'src/method_channel.dart';
import 'src/platform_interface.dart';

export 'src/capture_result.dart';
export 'src/controller.dart';
export 'src/platform_interface.dart' show ByrsaCapturePlatform, CaptureOptions;
export 'src/quad.dart';
export 'src/stability.dart';
export 'src/widgets/capture_preview.dart';
export 'src/widgets/quad_overlay.dart';

/// Registers the default platform implementation.
///
/// Called by Flutter's plugin registrant; call it yourself only when replacing
/// the platform implementation in a test.
void registerByrsaCapture() {
  ByrsaCapturePlatform.instance = MethodChannelByrsaCapture();
}
