// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// The engine behind [byrsa_ocr] on phones: Ente's MIT-licensed `mobile_ocr`,
/// which is Apple Vision on iOS and PP-OCRv5 through ONNX Runtime on Android,
/// with no Google Play Services.
///
/// This package exists to hold one thing: the git dependency. `byrsa_ocr`
/// itself has none, which is what keeps it publishable and adoptable.
library;

import 'package:byrsa_ocr/byrsa_ocr.dart';

import 'src/mobile_ocr_engine.dart';

export 'src/mobile_ocr_engine.dart' show MobileOcrEngine;

/// Installs `mobile_ocr` as the engine `byrsa_ocr` will use.
///
/// Call it once at startup, before the first recognition.
void registerMobileOcrEngine() {
  ByrsaOcrPlatform.instance = MobileOcrEngine();
}
