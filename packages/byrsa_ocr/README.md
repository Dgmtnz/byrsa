<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# byrsa_ocr

On-device text recognition behind one Dart API: **Apple Vision** on iOS,
**PP-OCR through ONNX Runtime** on Android. No Google Play Services.

Nothing is uploaded. The only network request this package can make is
downloading the Android models, and only when you ask for it.

## It delegates, on purpose

The platform-specific half is [Ente's `mobile_ocr`](https://github.com/ente-io/mobile_ocr)
(MIT), which already does it well: Vision on iOS, PP-OCRv5 through ONNX Runtime
on Android, with its own model download and checksum verification. Rewriting
that would take months and leave the ecosystem with two half-maintained copies
of the same thing.

What this package adds is the part that should not be written twice:

- **A stable API** that does not change when the engine underneath does.
- **Reading order**, reconstructed in Dart so it is identical on both platforms
  and unit-tested on a laptop. A scan that reads correctly on screen and pastes
  as scrambled text is the usual symptom of skipping this.
- **Word boxes.** Both engines return one polygon per *block*, which can be a
  whole line. A searchable PDF needs a box per word or the selection drifts
  along the line, so character boxes are regrouped into words where the engine
  gives them, and split by proportion where it does not — an approximation that
  is marked in the source rather than hidden.
- **A result type with no `dart:ui` in it**, so a pure-Dart PDF writer or a
  server can consume it.

## Usage

```dart
registerByrsaOcr();

const ocr = ByrsaOcr();
final readiness = await ocr.readiness();
if (!readiness.ready) {
  // readiness.missingBytes is what to show the user before asking.
  await ocr.prepare(onProgress: (received, total) { ... });
}

final result = await ocr.recognise(imagePath: page, languages: ['es', 'en']);
print(result.text);      // reading order, one line per line
print(result.engine);    // 'apple-vision' or 'pp-ocr-onnx'
```

`result.engine` is on the result rather than in a log, because a number
measured with one engine says nothing about the other and the benchmark has to
be able to tell them apart.

## Not on pub.dev yet, and why

pub.dev refuses packages with git dependencies, and `mobile_ocr` is not
published there. So this package cannot be either.

The fix is an upstream ask, not a reimplementation:
[`docs/upstream/mobile-ocr-pub-dev.md`](../../docs/upstream/mobile-ocr-pub-dev.md).
Until then, depend on it by path or by git.

## Languages

Spanish, English, French, German, Italian and Portuguese are the six the
project measures. Coverage and character error rate per language are pending
measurement on hardware; nothing is claimed here until the benchmark has run.

## Licence

Apache-2.0. Part of [Byrsa](https://github.com/dgmtnz/byrsa).
