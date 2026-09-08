<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# mobile_ocr: please publish to pub.dev

**Repository:** `github.com/ente-io/mobile_ocr`
**Status:** draft, ready to file

---

## Why this matters to Byrsa

`byrsa_ocr` is a thin layer over `mobile_ocr`: a stable API, reading-order
reconstruction, a confidence policy, and a result type with no `dart:ui` in it
so a pure-Dart PDF writer can consume it. Delegating rather than reimplementing
is the right call — `mobile_ocr` already does the platform-specific half well,
and the ecosystem does not need a second half-maintained PP-OCR pipeline.

The one thing that blocks it: pub.dev refuses a package with a git dependency,
so `byrsa_ocr` cannot be published while `mobile_ocr` is not.

---

## Issue text

**Title:** Publish `mobile_ocr` to pub.dev

`mobile_ocr` is, as far as I can tell, the only maintained Flutter plugin that
does on-device OCR on both platforms **without Google Play Services** — Apple
Vision on iOS, PP-OCRv5 through ONNX Runtime on Android, models downloaded and
checksum-verified at runtime. For anyone shipping through F-Droid or onto
de-Googled devices, that combination is currently unique, and the alternative
is ML Kit, which is not an alternative at all.

It is not on pub.dev, which has a consequence beyond convenience: **pub.dev
rejects packages that declare git dependencies**, so no package that builds on
`mobile_ocr` can be published either. That quietly caps how far the work can
travel — the plugin can be used by applications, but not built upon by other
packages.

Would you consider publishing it? Concretely, that needs:

- a `repository:` field in `pubspec.yaml` pointing at this repository
  (`homepage:` currently points at a personal fork);
- a `LICENSE` file at the package root — the README says MIT;
- a `CHANGELOG.md`;
- a note in the README about the licensing of the PaddleOCR-derived models,
  which are downloaded rather than bundled and are worth stating explicitly for
  downstream auditors.

I would be glad to send a pull request with all four if that would help.

### What I am building

An Apache-2.0 set of Flutter packages for document capture, rectification and
searchable-PDF export, targeting F-Droid, with a public benchmark of fifty real
documents. `mobile_ocr` is the OCR engine, credited as such. Any fixes I make
to it will come back here as patches.
