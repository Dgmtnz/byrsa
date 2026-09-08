// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// On-device text recognition behind one Dart API.
///
/// Apple Vision on iOS, PP-OCR through ONNX Runtime on Android. **No Google
/// Play Services**, so the result can ship on F-Droid.
///
/// Nothing is uploaded. The only network request this package can make is
/// downloading the Android models, which happens when the caller asks for it
/// and not before.
library;

import 'src/mobile_ocr_engine.dart';
import 'src/ocr_types.dart';
import 'src/platform_interface.dart';

export 'src/ocr_types.dart';
export 'src/platform_interface.dart' show ByrsaOcrPlatform, OcrReadiness;
export 'src/mobile_ocr_engine.dart' show MobileOcrEngine;
export 'src/reading_order.dart';

/// Registers the default engine.
///
/// Call this once at startup. It is explicit rather than automatic so that a
/// test — or a future native implementation — can put something else in its
/// place without fighting a plugin registrant.
void registerByrsaOcr() {
  ByrsaOcrPlatform.instance = MobileOcrEngine();
}

/// Convenience facade over [ByrsaOcrPlatform].
class ByrsaOcr {
  const ByrsaOcr();

  ByrsaOcrPlatform get _platform => ByrsaOcrPlatform.instance;

  Future<OcrReadiness> readiness() => _platform.readiness();

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
