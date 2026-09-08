// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ocr_types.dart';

/// State of the models an engine needs.
class OcrReadiness {
  const OcrReadiness({
    required this.ready,
    required this.engine,
    this.missingBytes = 0,
    this.reason,
  });

  final bool ready;

  /// `apple-vision` or `pp-ocr-onnx`.
  final String engine;

  /// What a first run would have to download. Zero on iOS: Vision is part of
  /// the system, which is the whole reason it is used there.
  final int missingBytes;

  final String? reason;
}

/// One API, two very different engines underneath.
///
/// Apple Vision on iOS because it is part of the system and costs nothing in
/// binary size; PP-OCR through ONNX Runtime on Android because the only
/// comparable system option there is ML Kit, which is delivered by Google Play
/// Services and would make the result unshippable on F-Droid.
///
/// The asymmetry is real and this interface does not pretend otherwise: quality
/// and speed differ, and every number the project publishes says which engine
/// produced it.
abstract class ByrsaOcrPlatform extends PlatformInterface {
  ByrsaOcrPlatform() : super(token: _token);

  static final Object _token = Object();
  static ByrsaOcrPlatform? _instance;

  static ByrsaOcrPlatform get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError(
        'No byrsa_ocr implementation registered for this platform.',
      );
    }
    return instance;
  }

  static set instance(ByrsaOcrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether recognition can run right now, and what it would cost to get
  /// there if not.
  Future<OcrReadiness> readiness();

  /// Downloads whatever the engine is missing.
  ///
  /// This is the one moment the application touches the network, and it only
  /// happens because the user asked for OCR. Progress is reported so the user
  /// can watch it and change their mind.
  Future<void> prepare({void Function(int received, int total)? onProgress});

  /// Recognises text in the image at [imagePath].
  ///
  /// [languages] are BCP-47 tags. Engines differ in what they do with the hint:
  /// Vision uses it to pick a language model, PP-OCR uses it to pick a
  /// character dictionary.
  Future<OcrResult> recognise({
    required String imagePath,
    List<String> languages = const <String>['es', 'en'],
    double minimumConfidence = 0.5,
  });

  /// Language tags the engine on this device can actually handle.
  Future<List<String>> supportedLanguages();
}
