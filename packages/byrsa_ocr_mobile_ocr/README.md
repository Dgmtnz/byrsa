<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# byrsa_ocr_mobile_ocr

The engine behind [`byrsa_ocr`](../byrsa_ocr) on phones: Ente's MIT-licensed
[`mobile_ocr`](https://github.com/ente-io/mobile_ocr), which is **Apple Vision
on iOS** and **PP-OCRv5 through ONNX Runtime on Android**, with no Google Play
Services.

```dart
import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_ocr_mobile_ocr/byrsa_ocr_mobile_ocr.dart';

registerMobileOcrEngine();
final result = await const ByrsaOcr().recognise(imagePath: page);
```

## This package exists to hold one thing

The git dependency.

pub.dev refuses any package that declares one, and `mobile_ocr` is not
published there. Putting the binding here means that constraint costs exactly
one unpublishable package instead of blocking `byrsa_ocr`, which is the part
other people want to adopt.

If Ente publishes `mobile_ocr` — we have
[asked, with an offer to send the pull request](../../docs/upstream/mobile-ocr-pub-dev.md) —
this package becomes publishable too, by deleting four lines.

## What it adds over calling `mobile_ocr` directly

Both engines return one polygon per **block**, which is often a whole line. A
searchable PDF needs a box per **word**, or the selection drifts along the line
and copy-paste comes out misaligned against the image.

So blocks are split into words: from character boxes where the engine provides
them, and by proportion of text width where it does not. The second is an
approximation, it is marked as one in the source, and it is tested — words come
out in order, non-overlapping, spanning the block, with wider words getting
wider boxes.

## Platform status

| | Android | iOS |
|---|---|---|
| Compiles | **verified** | not verified — no macOS machine |
| Recognition measured | **no** | **no** |

No accuracy or timing figure is claimed. The repository's `UNVERIFIED.md` lists
the commands that would produce them.

## Licence

Apache-2.0. `mobile_ocr` is MIT; the PaddleOCR-derived models it downloads carry
their own licensing, which the repository's `models.json` tracks and marks
`UNAUDITED` until a human has read each model card.
