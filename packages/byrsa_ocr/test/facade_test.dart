// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:test/test.dart';

class FakeEngine extends ByrsaOcrPlatform {
  int prepareCount = 0;

  @override
  Future<OcrReadiness> readiness() async =>
      const OcrReadiness(ready: false, engine: 'fake', missingBytes: 1024);

  @override
  Future<void> prepare({void Function(int, int)? onProgress}) async {
    prepareCount++;
    onProgress?.call(1024, 1024);
  }

  @override
  Future<List<String>> supportedLanguages() async => const <String>['es'];

  @override
  Future<OcrResult> recognise({
    required String imagePath,
    List<String> languages = const <String>['es', 'en'],
    double minimumConfidence = 0.5,
  }) async =>
      OcrResult(
        lines: const ReadingOrder().group(<OcrWord>[
          OcrWord(
              text: imagePath, box: const OcrBox(0, 0, 10, 10), confidence: 1),
        ]),
        imageWidth: 10,
        imageHeight: 10,
        engine: 'fake',
        duration: Duration.zero,
      );
}

void main() {
  test('says how to fix it when no engine is registered', () {
    // The failure a first-time user hits. It has to name the package and the
    // call, not just report a null.
    expect(
      () => ByrsaOcrPlatform.instance,
      throwsA(
        isA<StateError>()
            .having(
                (e) => e.message, 'message', contains('byrsa_ocr_mobile_ocr'))
            .having((e) => e.message, 'message',
                contains('registerMobileOcrEngine')),
      ),
    );
  });

  test('an engine written outside this package works, with no Flutter in sight',
      () {
    // The whole point of the inversion: anyone can supply an engine, and the
    // API package pulls in nothing to allow it.
    final engine = FakeEngine();
    ByrsaOcrPlatform.instance = engine;

    expect(const ByrsaOcr().readiness(), completion(isA<OcrReadiness>()));
    expect(
      const ByrsaOcr().recognise(imagePath: 'hola.jpg'),
      completion(isA<OcrResult>().having((r) => r.text, 'text', 'hola.jpg')),
    );
  });

  test('forwards download progress from the engine to the caller', () async {
    ByrsaOcrPlatform.instance = FakeEngine();
    var seen = 0;
    await const ByrsaOcr()
        .prepare(onProgress: (received, total) => seen = received);
    expect(seen, 1024);
  });
}
