<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# byrsa_ocr

A stable Dart API for on-device text recognition, plus the logic around it that
should not be written twice: **reading order, word boxes, and a confidence
policy**.

Pure Dart. No Flutter, no platform channels, no native code, and **no engine**.
Two dependencies, both tiny: `meta` and `plugin_platform_interface`.

## Why there is no engine in here

An engine binding drags platform code, native libraries and sometimes a git
dependency behind it. The API does not have to.

Keeping them apart means this package can be published, adopted, and used
somewhere there is no phone at all — a server, a CLI, a test — while the engine
is a separate, replaceable choice:

```
byrsa_ocr                 the API and the logic          pure Dart, publishable
byrsa_ocr_mobile_ocr      Apple Vision + PP-OCR ONNX     Flutter, on-device
your_engine               whatever you already use       yours
```

It also means a real constraint stops being contagious. `mobile_ocr`, the
MIT-licensed plugin Byrsa uses on phones, is not on pub.dev, and pub.dev
refuses any package with a git dependency. With the binding in its own package
that costs exactly one unpublishable package instead of blocking the part
people want to adopt.

## Usage

```dart
import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_ocr_mobile_ocr/byrsa_ocr_mobile_ocr.dart';

void main() {
  registerMobileOcrEngine();   // or your own engine
  runApp(...);
}
```

```dart
const ocr = ByrsaOcr();

final readiness = await ocr.readiness();
if (!readiness.ready) {
  // readiness.missingBytes is what to show the user before asking.
  await ocr.prepare(onProgress: (received, total) { ... });
}

final result = await ocr.recognise(imagePath: page, languages: ['es', 'en']);
print(result.text);      // reading order, one line per line
print(result.engine);    // travels with the result, always
```

Forget to register an engine and you get a `StateError` that names the package
and the call, not a null somewhere deeper.

## Writing an engine

Extend `ByrsaOcrPlatform`, return words with boxes, and everything else — line
grouping, ordering, filtering — is already done for you.
[`example/byrsa_ocr_example.dart`](example/byrsa_ocr_example.dart) is a
complete engine in twenty lines, and it runs with `dart run`.

## What this package actually does for you

- **Reading order.** Detectors return boxes in network order. A scan that reads
  correctly on screen and pastes as scrambled text is the usual symptom of
  skipping this step. Grouped by vertical overlap, ordered top to bottom and
  left to right, and unit-tested.
- **Types with no `dart:ui` in them.** `OcrBox` is four doubles, so the result
  can be handed straight to a pure-Dart PDF writer.
- **`result.engine` on the result.** A number measured with one engine says
  nothing about another, so the engine is part of the answer rather than a log
  line.

Deliberately not here: column detection. Grouping is right for a single column
of left-to-right text — receipts, invoices, letters, book pages — and a
two-column journal page will interleave. That ceiling is written in the source
with its upgrade path, and the project's benchmark is what decides whether the
upgrade is worth it.

## Licence

Apache-2.0. Part of [Byrsa](https://github.com/dgmtnz/byrsa).
