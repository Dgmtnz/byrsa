// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// byrsa_ocr is the API, not the engine. This example shows the whole contract
// against an engine invented in twenty lines, which is also how you would plug
// in a recogniser this project has never heard of:
//
//   dart run example/byrsa_ocr_example.dart
//
// On a phone you would register `byrsa_ocr_mobile_ocr` instead and the rest of
// this file would not change. That is the point of the split.

import 'package:byrsa_ocr/byrsa_ocr.dart';

class EchoEngine extends ByrsaOcrPlatform {
  @override
  Future<OcrReadiness> readiness() async =>
      const OcrReadiness(ready: true, engine: 'echo');

  @override
  Future<void> prepare({void Function(int, int)? onProgress}) async {}

  @override
  Future<List<String>> supportedLanguages() async => const <String>['es'];

  @override
  Future<OcrResult> recognise({
    required String imagePath,
    List<String> languages = const <String>['es', 'en'],
    double minimumConfidence = 0.5,
  }) async {
    // A real engine returns these from a neural network. The shape is the
    // contract: text, a box in image pixels, and a confidence.
    const words = <OcrWord>[
      OcrWord(
          text: 'Importe', box: OcrBox(120, 300, 310, 346), confidence: 0.98),
      OcrWord(text: 'total', box: OcrBox(322, 302, 452, 346), confidence: 0.97),
      OcrWord(
          text: '1.234,56', box: OcrBox(470, 300, 700, 346), confidence: 0.91),
      OcrWord(
          text: 'FACTURA', box: OcrBox(120, 200, 420, 260), confidence: 0.99),
    ];
    return OcrResult(
      lines: ReadingOrder(minimumConfidence: minimumConfidence).group(words),
      imageWidth: 1240,
      imageHeight: 1754,
      engine: 'echo',
      duration: const Duration(milliseconds: 1),
    );
  }
}

Future<void> main() async {
  ByrsaOcrPlatform.instance = EchoEngine();

  const ocr = ByrsaOcr();
  print('ready: ${(await ocr.readiness()).ready}');

  final result = await ocr.recognise(imagePath: 'invoice.jpg');

  // Reading order is reconstructed here, in Dart, so it is the same whatever
  // the engine returned and in whatever order.
  print('--- text ---\n${result.text}');

  // Word boxes, which is what a searchable PDF needs. Feed them straight to
  // dart_searchable_pdf: neither package depends on the other.
  for (final word in result.words) {
    print('${word.text.padRight(10)} ${word.box}');
  }
}
