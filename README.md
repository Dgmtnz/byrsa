<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Byrsa

**An on-device document capture, rectification and OCR stack for Flutter.**

Byrsa is not primarily an application. It is four reusable Flutter/Dart packages,
plus a reference application that proves they compose end to end.

| Package | What it does | Licence | Status |
|---|---|---|---|
| [`byrsa_capture`](packages/byrsa_capture) | Live edge detection and perspective correction, no Google Play Services | Apache-2.0 | in development |
| [`byrsa_restore`](packages/byrsa_restore) | Page rectification (UVDoc) and shadow removal (DocShadow) as quantised ONNX, plus a classical baseline | Apache-2.0 | in development |
| [`byrsa_ocr`](packages/byrsa_ocr) | On-device OCR behind one Dart API: Apple Vision on iOS, PP-OCR ONNX on Android | Apache-2.0 | in development |
| [`dart_searchable_pdf`](packages/dart_searchable_pdf) | Pure-Dart PDF invisible text layer (text render mode 3) | Apache-2.0 | in development |
| [`app`](app) | Byrsa, the reference application | GPL-3.0-or-later | in development |
| [`harness`](harness) | Reproducible evaluation harness: CER, timing, memory | Apache-2.0 | in development |

A developer who only needs searchable PDFs takes `dart_searchable_pdf` and ignores
the rest. That is the point.

## The privacy guarantee, stated precisely

> No document ever leaves the device. The only network traffic the application can
> generate is a model download that the user starts explicitly, from a pinned URL
> with SHA-256 verification.

The application declares Android's `INTERNET` permission because of that download.
Saying "the build asks for no network permission" would be false, so we do not say it.

## No Google Play Services

Capture is `doclens` (MIT) and our own pipeline; OCR on Android is PP-OCR through
ONNX Runtime. Nothing in the main build depends on Play Services, so the packages
are usable in F-Droid and other independent distributions.

## Platform status — read this before believing any number

Development happens on Linux. There is currently no macOS machine in the project,
therefore:

- Every iOS implementation is **written and kept compiling in CI**, with symmetric
  Dart APIs.
- **No iOS measurement exists, and none is claimed.** Anything not measured on real
  hardware lives in [`UNVERIFIED.md`](UNVERIFIED.md) together with the exact command
  that would verify it.


## Licensing

Packages are Apache-2.0 so that anyone can adopt them; the application is
GPL-3.0-or-later. The repository is [REUSE](https://reuse.software) compliant —
every file carries an SPDX header or a `REUSE.toml` entry.

## Repository layout

```
packages/   the four deliverable packages (Apache-2.0)
app/        Byrsa, the reference application (GPL-3.0-or-later)
harness/    evaluation harness — 50 real documents, CER and timing
docs/       plan, decisions, evaluation protocol
```

## Building

Requires Flutter (see `.fvmrc`/CI for the pinned version).

```
dart pub get                    # workspace-wide, no melos needed
dart test packages/dart_searchable_pdf   # pure Dart, runs anywhere
flutter test                    # everything else
```
