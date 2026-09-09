// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// A stable API for on-device text recognition, and the logic around it that
/// should not be written twice: reading order, word boxes, and a confidence
/// policy.
///
/// **This package contains no engine.** It is pure Dart — no Flutter, no
/// platform channels, no native code — and an application supplies the engine
/// it wants by registering one. Byrsa ships `byrsa_ocr_mobile_ocr`, which is
/// Apple Vision on iOS and PP-OCR through ONNX Runtime on Android, with no
/// Google Play Services.
///
/// The split is deliberate. An engine binding drags platform code, native
/// libraries and sometimes a git dependency behind it; the API does not have
/// to, and anything reusable lives on this side of the line.
library;

import 'src/ocr_types.dart';
import 'src/platform_interface.dart';

export 'src/ocr_types.dart';
export 'src/platform_interface.dart' show ByrsaOcrPlatform, OcrReadiness;
export 'src/reading_order.dart';

/// Convenience facade over the registered [ByrsaOcrPlatform].
///
/// Throws a [StateError] naming the fix if no engine has been registered,
/// rather than failing somewhere deeper with a null.
class ByrsaOcr {
  const ByrsaOcr();

  ByrsaOcrPlatform get _platform => ByrsaOcrPlatform.instance;

  /// Whether recognition can run right now, and what it would cost to get
  /// there if not.
  Future<OcrReadiness> readiness() => _platform.readiness();

  /// Downloads whatever the engine is missing.
  ///
  /// This is the one moment an application using this package touches the
  /// network, and only because the caller asked.
  Future<void> prepare({void Function(int received, int total)? onProgress}) =>
      _platform.prepare(onProgress: onProgress);

  Future<OcrResult> recognise({
    required String imagePath,
    List<String> languages = const <String>['es', 'en'],
    double minimumConfidence = 0.5,
  }) =>
      _platform.recognise(
        imagePath: imagePath,
        languages: languages,
        minimumConfidence: minimumConfidence,
      );

  Future<List<String>> supportedLanguages() => _platform.supportedLanguages();
}
