// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:mobile_ocr/mobile_ocr.dart';

/// Implements [ByrsaOcrPlatform] on top of Ente's MIT-licensed `mobile_ocr`
/// plugin.
///
/// `mobile_ocr` already does the hard, platform-specific half: Apple Vision on
/// iOS, PP-OCRv5 through ONNX Runtime on Android, with its own model download
/// and checksum verification and no dependency on Play Services. Rewriting that
/// would take months and leave the ecosystem with two half-maintained copies of
/// the same thing.
///
/// What this layer adds is everything that should not be written twice: a
/// stable API that does not change when the engine does, reading-order
/// reconstruction that is identical on both platforms and unit-tested on a
/// laptop, a confidence policy, and a result type that a pure-Dart PDF writer
/// can consume without pulling in Flutter.
class MobileOcrEngine extends ByrsaOcrPlatform {
  MobileOcrEngine({MobileOcr? plugin}) : _plugin = plugin ?? MobileOcr();

  final MobileOcr _plugin;

  /// Rough size of the PP-OCRv5 detector and recogniser together.
  ///
  /// Used only to tell the user what a first run will cost. It is deliberately
  /// an approximation and labelled as one; the authoritative number comes from
  /// the plugin once a download starts.
  static const int androidModelBytes = 20 * 1024 * 1024;

  @override
  Future<OcrReadiness> readiness() async {
    final engine = Platform.isIOS ? 'apple-vision' : 'pp-ocr-onnx';
    if (Platform.isIOS) {
      // Vision is part of the system: nothing to download, ever.
      return OcrReadiness(ready: true, engine: engine);
    }
    final availability = await _plugin.getModelAvailability();
    final ready = availability.detectorReady && availability.recognizerReady;
    return OcrReadiness(
      ready: ready,
      engine: engine,
      missingBytes: ready ? 0 : androidModelBytes,
      reason: ready ? null : 'The PP-OCR models have not been downloaded yet.',
    );
  }

  @override
  Future<void> prepare(
      {void Function(int received, int total)? onProgress}) async {
    if (Platform.isIOS) return;
    // `mobile_ocr` reports completion rather than progress, so the callback
    // gets one honest event instead of a fabricated animation.
    onProgress?.call(0, androidModelBytes);
    await _plugin.prepareModels();
    onProgress?.call(androidModelBytes, androidModelBytes);
  }

  @override
  Future<OcrResult> recognise({
    required String imagePath,
    List<String> languages = const <String>['es', 'en'],
    double minimumConfidence = 0.5,
  }) async {
    final stopwatch = Stopwatch()..start();
    final detection = await _plugin.detectText(
      imagePath: imagePath,
      // Ask for everything and filter here, so the confidence policy is one
      // place and the same on both platforms.
      includeAllConfidenceScores: true,
    );

    final words = <OcrWord>[
      for (final block in detection.blocks) ...blockToWords(block),
    ];

    return OcrResult(
      lines: ReadingOrder(minimumConfidence: minimumConfidence).group(words),
      imageWidth: detection.imageSize.width.round(),
      imageHeight: detection.imageSize.height.round(),
      engine: Platform.isIOS ? 'apple-vision' : 'pp-ocr-onnx',
      duration: stopwatch.elapsed,
    );
  }

  /// Splits a detected block into words with their own boxes.
  ///
  /// Both engines return a polygon per *block*, which can be a whole line. A
  /// searchable PDF needs a box per word or the selection drifts along the
  /// line, so where character boxes are available they are regrouped into
  /// words, and where they are not the block's box is divided in proportion to
  /// the width of each word's text.
  static List<OcrWord> blockToWords(TextBlock block) {
    final box = OcrBox.ofPolygon(<({double x, double y})>[
      for (final point in block.points) (x: point.dx, y: point.dy),
    ]);

    if (block.characters.isNotEmpty) {
      return _wordsFromCharacters(block, box);
    }
    return _wordsByProportion(block.text, box, block.confidence);
  }

  static List<OcrWord> _wordsFromCharacters(TextBlock block, OcrBox blockBox) {
    final words = <OcrWord>[];
    var current = <CharacterBox>[];

    void flush() {
      if (current.isEmpty) return;
      final text = current.map((c) => c.text).join();
      if (text.trim().isNotEmpty) {
        words.add(OcrWord(
          text: text,
          confidence: current.map((c) => c.confidence).reduce((a, b) => a + b) /
              current.length,
          box: OcrBox.ofPolygon(<({double x, double y})>[
            for (final character in current)
              for (final point in character.points) (x: point.dx, y: point.dy),
          ]),
        ));
      }
      current = <CharacterBox>[];
    }

    for (final character in block.characters) {
      if (character.text.trim().isEmpty) {
        flush();
      } else {
        current.add(character);
      }
    }
    flush();
    return words.isEmpty
        ? _wordsByProportion(block.text, blockBox, block.confidence)
        : words;
  }

  static List<OcrWord> _wordsByProportion(
    String text,
    OcrBox box,
    double confidence,
  ) {
    final tokens =
        text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const <OcrWord>[];
    if (tokens.length == 1) {
      return <OcrWord>[
        OcrWord(text: tokens.single, box: box, confidence: confidence)
      ];
    }

    // Character count is a crude proxy for width, but it is the only signal
    // available when the engine gives one polygon for a whole line. It is
    // marked here rather than hidden: an engine that returns character boxes
    // takes the branch above and is always better.
    final totalCharacters =
        tokens.fold<int>(0, (sum, token) => sum + token.length) +
            tokens.length -
            1;
    final unit = box.width / totalCharacters;

    final words = <OcrWord>[];
    var cursor = box.left;
    for (var i = 0; i < tokens.length; i++) {
      final width = unit * tokens[i].length;
      words.add(OcrWord(
        text: tokens[i],
        box: OcrBox(cursor, box.top, cursor + width, box.bottom),
        confidence: confidence,
      ));
      cursor += width + unit; // one unit for the space
    }
    return words;
  }

  @override
  Future<List<String>> supportedLanguages() async => Platform.isIOS
      // Vision's Latin-script recogniser, as of iOS 16.
      ? const <String>['en', 'es', 'fr', 'de', 'it', 'pt']
      // PP-OCRv5's Latin dictionary covers the same six.
      : const <String>['en', 'es', 'fr', 'de', 'it', 'pt'];
}
