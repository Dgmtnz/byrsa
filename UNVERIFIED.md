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
| U-21 | Every model in `models.json` has a real, computed SHA-256 | `dart run tool/pin_models.dart --verify`, 2026-09-08 | 5 of 5 pinned. |
| U-27 | `doclens` is MIT | read its `LICENSE`, 2026-09-09 | MIT, © 2026 Govind Maheshwari. |
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
| U-31 | How long restoration really takes on a phone. On a desktop it is 755 ms to restore and 904 ms to encode a 6.8 MP page; a mid-range phone should be several times slower and that is a guess, not a measurement | mid-range Android | `tool/bench_restore.dart` logic inside the example app | OPEN |
| U-22 | DocShadow-SD7K survives quantisation at a usable size **and** quality. It is 120 MB as exported in fp32 — four times UVDoc — so this is not an optimisation, it is the precondition for shipping it at all | mid-range Android | quantise to int8, then `packages/byrsa_restore/example` in release, and the harness for quality | OPEN |
| U-23 | UVDoc's real curvature ceiling: where dewarping stops helping and starts hurting | mid-range Android + the 50-document set | the harness, with and without the stage | OPEN |
| U-24 | The Android quad detector's hit rate on real photographs, against its documented ceiling | mid-range Android + the 50-document set | `packages/byrsa_capture/example`, corners annotated by hand | OPEN |

## Needs only a desktop we already have

| # | Claim | Machine needed | Exact command | Status |
|---|---|---|---|---|
| U-17 | Searchable PDFs select and search correctly in **Chrome / pdf.js** | any Linux desktop | open `harness/out/*.pdf` in Chrome, Ctrl+F a known word | OPEN |
| U-18 | Poppler round-trip on the real 50-document set (CI only covers synthetic pages so far) | this machine | `dart test packages/dart_searchable_pdf` then the harness | OPEN |

## Needs an answer from a third party

| # | Question | Who | Status |
|---|---|---|---|
| U-13 | Does F-Droid accept runtime model downloads, or does it flag them? (§4.8) | F-Droid forum / RFP | OPEN |
| U-14 | Exact licence of every PP-OCR model actually distributed | PaddleOCR model cards, one by one | OPEN |
| U-15 | Acceptable hourly rate for an individual applicant in Spain | NLnet office hour, 30 Sep 2026 | OPEN |
| U-16 | Is the absence of iOS hardware a problem for the reviewers? | NLnet office hour, 30 Sep 2026 | OPEN |
| U-25 | Will `doclens` accept making the ML Kit dependency optional? (`docs/upstream/doclens-play-services.md`) | doclens maintainers | DRAFTED, not yet filed |
| U-32 | `mobile_ocr` applies the Kotlin Gradle Plugin, which Flutter warns will stop building in a future release. Today a warning, later a hard break for every dependent | Ente maintainers | FOUND 2026-09-09, to file with the publish request |
| U-26 | Will Ente publish `mobile_ocr` to pub.dev? No longer blocks us since D-027, and asked as a favour to the ecosystem rather than a condition (`docs/upstream/mobile-ocr-pub-dev.md`) | Ente maintainers | DRAFTED, not yet filed |
