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
| [`byrsa_restore_onnx`](packages/byrsa_restore_onnx) | The neural stages: page dewarping through ONNX Runtime | Apache-2.0 | in development |
| [`byrsa_restore`](packages/byrsa_restore) | Shadow removal and illumination flattening in pure Dart, plus page dewarping through a UVDoc ONNX grid | Apache-2.0 | in development |
| [`byrsa_ocr`](packages/byrsa_ocr) | A stable Dart API for on-device OCR — pure Dart, no engine, no Flutter | Apache-2.0 | in development |
| [`byrsa_ocr_mobile_ocr`](packages/byrsa_ocr_mobile_ocr) | The engine for phones: Apple Vision on iOS, PP-OCR ONNX on Android | Apache-2.0 | in development |
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

Capture is our own CameraX / AVFoundation plugin (`byrsa_capture`); OCR on Android is PP-OCR through
ONNX Runtime. Nothing in the main build depends on Play Services, so the packages
are usable in F-Droid and other independent distributions.

## Platform status — read this before believing any number

Development happens on Linux. There is currently no macOS machine in the project,
therefore:

- Every iOS implementation is **written**, with symmetric Dart APIs, and **none
  of it has ever been compiled**. There is a macOS job in the CI workflow, it is
  marked `continue-on-error`, and CI has never run — see below.
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

## What is already verified

Each row is a command you can run yourself, and the result was produced on the
machine named in [`docs/measurements.md`](docs/measurements.md).

**They do not run in CI.** A workflow exists at `.github/workflows/ci.yml` and
has never executed once: this repository has no git remote and has never been
pushed. Until it is, every one of these is a local result, and the row that used
to say "in CI" said something untrue.

| Claim | How it is checked |
|---|---|
| The Android build contains **no** Google Play Services, in the code **or the manifest** | `tool/check_no_play_services.sh` on the application's arm64 **release** APK. The manifest half of that check was added on 2026-09-16, after it found a Play Services service that `image_picker_android` had injected and the previous code-only check could not see |
| Searchable PDFs are readable by Poppler, accents included | `pdftotext -layout` round-trip in the test suite |
| The invisible text layer lines up with the image | rendered word width asserted equal to the OCR box, for narrow, wide and accented words |
| PDF output is byte-for-byte reproducible | same input, same bytes |
| Every downloadable model has a real, computed digest | `dart run tool/pin_models.dart --verify` |
| The documentation makes no unmeasured iOS claim | `tool/check_claims.sh` |
| The release application is **48.8 MB** on arm64, before any model download | `flutter build apk --release --split-per-abi` |
| Restoring a 12 MP page takes **0.6 s**, down from 55.9 s | `dart run tool/bench_restore.dart` |
| **205 tests** pass with no device, no models and no network | `flutter test` + `dart test` |
| `dart_searchable_pdf` and `byrsa_ocr` are publishable to pub.dev | `dart pub publish --dry-run` |

What is **not** verified is listed just as plainly in
[`UNVERIFIED.md`](UNVERIFIED.md), with the machine and the command that would
close each row.

## Building

Requires Flutter — the version is pinned in [`.fvmrc`](.fvmrc) and CI reads it
from there.

```
flutter pub get                                   # workspace-wide, no melos
flutter analyze
dart test packages/dart_searchable_pdf packages/byrsa_ocr harness   # pure Dart
flutter test packages/byrsa_capture packages/byrsa_restore \
             packages/byrsa_ocr_mobile_ocr app
dart run harness/bin/harness.dart validate        # the evaluation dataset
```

Poppler (`poppler-utils`) makes the searchable-PDF round-trip tests run rather
than skip. Install it.

## Reading further

- [`DECISIONS.md`](DECISIONS.md) — every design decision, with its cost. Entries
  marked `ratificar` are proposals awaiting final review.
- [`UNVERIFIED.md`](UNVERIFIED.md) — everything not yet measured, as a work order.
- [`docs/upstream/`](docs/upstream/) — patches and issues owed to the projects
  this one builds on.
- [`harness/dataset/README.md`](harness/dataset/README.md) — the fifty-document
  shot list and the rules on personal data.
