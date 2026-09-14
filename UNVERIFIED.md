<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# UNVERIFIED — claims we are not allowed to make yet

This file is a work order, not a disclaimer. Every row is something a future
contributor with the right machine can close in an afternoon.

Rules (see `CONTRIBUTING.md`):

- Nothing here may be stated as fact in the README, in a commit message, in a package
  description, or in the funding application.
- A row is closed by running the command, pasting the result, and moving the claim into
  the document that needed it — never by deleting the row.

Status legend: `BLOCKED` (needs hardware nobody in the project has) · `OPEN` (can be run
here, not run yet) · `CLOSED` (verified; keep the row with the result).

## Needs a macOS machine

| # | Claim that is currently unverified | Machine needed | Exact command | Status |
|---|---|---|---|---|
| U-01 | `byrsa_capture` builds for iOS | macOS + Xcode | `cd app && flutter build ios --no-codesign` | BLOCKED |
| U-02 | Apple Vision OCR path returns text and boxes at all | macOS + iPhone | `cd packages/byrsa_ocr/example && flutter run -d <ios-device>` | BLOCKED |
| U-03 | ONNX Runtime loads UVDoc on iOS at all (§4.6 — the project's biggest risk) | macOS + iPhone | `cd packages/byrsa_restore/example && flutter run -d <ios-device> --release` | BLOCKED |
| U-04 | iOS binary size with ONNX Runtime linked | macOS + Xcode | `flutter build ipa --analyze-size` | BLOCKED |
| U-05 | Peak memory of UVDoc inference on iOS | macOS + iPhone | Xcode Instruments, Allocations, one A4 photo | BLOCKED |
| U-06 | Searchable PDFs select correctly in **Preview** | macOS | open `harness/out/*.pdf`, ⌘F a known word | BLOCKED |
| U-07 | Any statement of iOS/Android parity whatsoever | macOS + iPhone | the harness, run on both | BLOCKED |

## Needs Adobe Acrobat

| # | Claim | Machine needed | Exact command | Status |
|---|---|---|---|---|
| U-08 | Searchable PDFs select correctly in **Acrobat Reader** | Windows/macOS + Acrobat | open `harness/out/*.pdf`, Ctrl+F a known word | BLOCKED |

## Closed — kept with the result

| # | Claim | How it was closed | Result |
|---|---|---|---|
| U-19 | The Android build contains no Google Play Services | `tool/check_no_play_services.sh` on the capture example's debug APK, 2026-09-08 | **0** `com.google.android.gms` / `com.google.mlkit` classes; 1717 `androidx.camera` references. Runs in CI on every push. |
| U-20 | Searchable PDFs are readable by Poppler, including accented Spanish | `dart test packages/dart_searchable_pdf`, 2026-09-08 | Words, accents and line grouping all round-trip through `pdftotext -layout`. |
| U-21 | Every model in `models.json` has a real, computed SHA-256 | `dart run tool/pin_models.dart --verify`, re-run 2026-09-14 | **8 of 8 files across 7 models, 0 changed.** The 2026-09-08 result read "5 of 5" and had since gone stale in a way nobody would have noticed: `uvdoc-grid` arrived in `b9586a5` with a `files` array, the tool had only ever been taught the single-`url` shape, and it crashed on a null check before reaching any model after the first. CI never ran it. Fixed, and the three PP-OCR digests were additionally hashed by hand and against the values `mobile_ocr` pins in `ModelManager.kt`. |
| U-27 | `doclens` is MIT | read its `LICENSE`, 2026-09-09 | MIT, © 2026 Govind Maheshwari. |
| U-37 | The SD7K dataset's licence, and whether the DocShadow weights inherit a restriction | read the publisher's own listing, 2026-09-13 | **MIT.** Declared by the University of Macau on the OpenXLab record the README designates as the download. No restriction inherited. The first pass reported "not found" because the API path 404s unless the slug's slash is percent-encoded — the 404 was the query, not the resource. |
| U-28 | `doclens`'s iOS side does not use ML Kit | grepped `ios/doclens/Sources`, 2026-09-09 | **No ML Kit at all.** It imports Vision and VisionKit — Apple's own. The Play Services problem is Android-only. |

## Needs a device and the fifty documents

| # | Claim | How to close it | Status |
|---|---|---|---|
| U-29 | Whether `doclens`'s quad detector beats ours, and in which conditions. Both algorithms are now read and understood; which one is better on real photographs is not | run both over the 50 documents with corners annotated by hand (D-028) | OPEN |

## Needs a physical Android phone

| # | Claim | Machine needed | Exact command | Status |
|---|---|---|---|---|
| U-09 | Live edge detection frame rate and thermal cost (§4.1, spike A) | mid-range Android | `packages/byrsa_capture/example`, DevTools timeline, 10 min run | OPEN |
| U-10 | UVDoc inference time and peak RAM on mid-range Android (§4.2, spike B) | mid-range Android | `packages/byrsa_restore/example`, release build | OPEN |
| U-11 | PP-OCR CER on real Spanish photographs (§4.4, spike C) | mid-range Android | `harness` run over the 50-document set | OPEN |
| U-12 | Application size after ABI splits | any Android | `flutter build apk --split-per-abi --analyze-size` | OPEN |
| U-30 | The camera permission flow actually works: the prompt appears, a refusal is reported as refused, and a permanent refusal is told apart from a retryable one. Written on both platforms, run on neither | any Android phone, then an iPhone | `packages/byrsa_capture/example`, deny then accept | OPEN |
| U-35 | How fast the platform JPEG encoder actually is. The Dart one is measured at ~900 ms for a 6.8 MP page; the native path is written for both platforms and has run on neither | any Android phone, then an iPhone | scan a page and read the `encode:native` stage timing the pipeline records | OPEN |
| U-31 | How long restoration really takes on a phone. On a desktop it is 755 ms to restore and 904 ms to encode a 6.8 MP page; a mid-range phone should be several times slower and that is a guess, not a measurement | mid-range Android | `tool/bench_restore.dart` logic inside the example app | OPEN |
| U-33 | Whether the Dart FFI package works against ONNX Runtime 1.27.0. The binding is built for 1.15.1; the root Gradle file drops the package's own copy and `tool/check_native_collisions.sh` asserts 1.27.0 in the release APK | any Android phone | run OCR on a release build | **NARROWED 2026-09-14.** PP-OCR inference ran on a device against the shipped runtime and returned correct text, so the C API is compatible in practice. Measured on a **debug** build; the release build, which is what the collision guard asserts, has not been exercised |
| U-34 | Whether the Dart FFI binding can open a session at all on a device | any Android phone | import a page with recognition on | **CLOSED for OCR 2026-09-14**: PP-OCR through ONNX ran on a device and returned text. `UvdocStage` specifically is still unexercised — the dewarp model was never downloaded — so the curved-page half of this row stays open |
| U-36 | Whether ANY neural shadow remover beats the classical baseline on real photographs. Measured on two synthetic shadow models, classical wins by 5.9-8.7 dB; both tests are biased toward it and neither settles the question. **Blocked on the 50-document set** — this is the first engineering decision that dataset gates, not just a marketing claim | the 50 real photographs | run the harness and compare CER, not PSNR | BLOCKED |
| U-22 | DocShadow-SD7K survives quantisation at a usable size **and** quality. It is 120 MB as exported in fp32 — four times UVDoc — so this is not an optimisation, it is the precondition for shipping it at all | mid-range Android | quantise to int8, then `packages/byrsa_restore/example` in release, and the harness for quality | OPEN |
| U-23 | UVDoc's real curvature ceiling: where dewarping stops helping and starts hurting | mid-range Android + the 50-document set | the harness, with and without the stage | OPEN |
| U-24 | The Android quad detector's hit rate on real photographs, against its documented ceiling | mid-range Android + the 50-document set | `packages/byrsa_capture/example`, corners annotated by hand | OPEN |

## Needs only a desktop we already have

| # | Claim | Machine needed | Exact command | Status |
|---|---|---|---|---|
| U-17 | Searchable PDFs select and search correctly in **Chrome / pdf.js** | any Linux desktop | open `harness/out/*.pdf` in Chrome, Ctrl+F a known word | OPEN |
| U-18 | Poppler round-trip on the real 50-document set (CI only covers synthetic pages so far) | this machine | `dart test packages/dart_searchable_pdf` then the harness | OPEN |
| U-40 | Character error rate of anything at all | any Android phone | import a corpus page and read `pages.text` | **FIRST VALUE 2026-09-14: CER 0.41%** (1 error in 242 characters, WER 5.41%, 36 word boxes) on `whiteboard-01`, an undamaged synthetic page, on a Mi 9T Pro. Every diacritic recovered. This is the easiest input the project will ever present: one page, rendered from a font, no damage. **Still owed**: the damaged half of the corpus, and real photographs |
| U-38 | Which upstream checkpoint `cls.onnx` actually is. Measured 2026-09-14: opset 11 / IR 6 / `p2o.` dim prefix / 35 unfolded BatchNorm / 2-class output — a different export generation from `det` and `rec`, and not the PP-OCRv5-era artefact `models.json` used to describe. That it is the legacy `ch_ppocr_mobile_v2.0_cls` is inference. The licence conclusion is Apache-2.0 either way; what is unverified is the identity | this machine | fetch `ch_ppocr_mobile_v2.0_cls_infer.tar` from paddleocr.bj.bcebos.com, export it with `paddle2onnx`, and compare the graph fingerprint with `docs/measurements.md` 2026-09-14 | OPEN |

## Needs an answer from a third party

| # | Question | Who | Status |
|---|---|---|---|
| U-13 | Does F-Droid accept runtime model downloads, or does it flag them? (§4.8) | F-Droid forum / RFP | OPEN |
| U-14 | Exact licence of every PP-OCR model actually distributed. **Mostly closed 2026-09-14** (`docs/model-licence-audit.md`): all four artefacts are Apache-2.0, and for det and rec that is a grant quoted off PaddlePaddle's own model card rather than an inference. Two things a third party still has to answer: PP-OCRv5's **training data is undisclosed**, so an inherited restriction cannot be ruled out by anyone outside Baidu; and `cls.onnx` is measurably a different-generation export than the other two, so *which* upstream model it is rests on inference (U-38) | Baidu/PaddleOCR for the corpus; Ente for the classifier's provenance | ask on the PaddleOCR issue tracker what PP-OCRv5 was trained on, and ask Ente which checkpoint `cls.onnx` was exported from | NARROWED 2026-09-14 |
| U-15 | Acceptable hourly rate for an individual applicant in Spain | NLnet office hour, 30 Sep 2026 | OPEN |
| U-16 | Is the absence of iOS hardware a problem for the reviewers? | NLnet office hour, 30 Sep 2026 | OPEN |
| U-39 | Whether `onnxruntime_flutter` is maintained at all. `compileSdkVersion 33` confirmed still present at `HEAD` on 2026-09-14, so the issue is correct — but the last commit is 2024-12-23, the last pub.dev release 2024-03-27, and 37 issues are open with several 2026 ones unanswered. Not archived | the maintainer, or the passage of time | file the issue and see; treat silence as the answer | OPEN |
| U-25 | Will `doclens` accept making the ML Kit dependency optional? (`docs/upstream/doclens-play-services.md`) | doclens maintainers | re-verify against `HEAD`, then file the issue and the two PRs | **READY 2026-09-14, not yet filed.** Re-checked against 0.0.12 / `e1fe7d7`: both `implementation` lines unchanged, still exactly 3 of 11 production Kotlin files using ML Kit, 0 in the six core files, 0 in the whole iOS tree, and the `QuadDetector.kt:26` comment intact. The maintainer merged two outside PRs on 2026-09-12 |
| U-32 | `mobile_ocr` **and `share_plus`** apply the Kotlin Gradle Plugin, which Flutter warns will stop building in a future release. Today a warning, later a hard break for every dependent. Widened 2026-09-14: the first Android build of the application printed both names, not just `mobile_ocr`, so the eventual break takes the export feature with it and not only OCR | Ente maintainers, and the `share_plus` maintainers | `cd app && flutter build apk --debug` prints the list | READY 2026-09-14, to file with the publish request |
| U-26 | Will Ente publish `mobile_ocr` to pub.dev? No longer blocks us since D-027, and asked as a favour to the ecosystem rather than a condition (`docs/upstream/mobile-ocr-pub-dev.md`) | Ente maintainers | file the licence-trace issue first, then the publish request | **READY 2026-09-14, not yet filed.** Re-check killed one of the four asks: the `LICENSE` file already exists. Two survive (`repository:` field, `CHANGELOG.md`) and the third became an offer rather than a request, since D-044 traced the licence the README leaves vague |
