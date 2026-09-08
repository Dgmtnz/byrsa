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

## Needs a physical Android phone

| # | Claim | Machine needed | Exact command | Status |
|---|---|---|---|---|
| U-09 | Live edge detection frame rate and thermal cost (§4.1, spike A) | mid-range Android | `packages/byrsa_capture/example`, DevTools timeline, 10 min run | OPEN |
| U-10 | UVDoc inference time and peak RAM on mid-range Android (§4.2, spike B) | mid-range Android | `packages/byrsa_restore/example`, release build | OPEN |
| U-11 | PP-OCR CER on real Spanish photographs (§4.4, spike C) | mid-range Android | `harness` run over the 50-document set | OPEN |
| U-12 | Application size after ABI splits and dartcv treeshaking | any Android | `flutter build apk --split-per-abi --analyze-size` | OPEN |

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
