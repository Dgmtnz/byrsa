<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# What this repository can already say in the application

The plan (`plan-escaner-open-source-flutter.md`) is the source of truth, and its
Annex A is the application draft. This file is the bridge: what is now
**measured and citable**, what is still a bracket only you can fill, and where
the numbers came from.

Rule §0.3 still holds — if a number changes, it changes in the plan first and
propagates here. Nothing below is an estimate.

---

## Measured, with the command that produced it

| Claim | Evidence | Where |
|---|---|---|
| `dart_searchable_pdf` and `byrsa_ocr` are publishable to pub.dev | `dart pub publish --dry-run`, zero warnings, checked in CI | `packages/*/pubspec.yaml` |
| The Android build contains **zero** Google Play Services classes | 0 `com.google.android.gms`/`com.google.mlkit` strings in the dex, against 1717 `androidx.camera` | `tool/check_no_play_services.sh`, in CI |
| Searchable PDFs round-trip through Poppler, accents included | 30 tests, including `pdftotext -layout` on generated pages with `Facturación`, `señor`, `ñandú`, `€` | `packages/dart_searchable_pdf/test` |
| Invisible-layer width matches the OCR box exactly | asserted for narrow, wide and accented words at three box sizes | `text_layer_test.dart` |
| PDF output is byte-for-byte reproducible | same input, same bytes, with a fixed creation date | `pdf_test.dart` |
| UVDoc ONNX is **31,684,150 bytes**, Apache-2.0 | downloaded and hashed 2026-09-08 | `models.json` |
| DocShadow-SD7K ONNX is **120,041,674 bytes** in fp32 | downloaded and hashed 2026-09-08 | `models.json` |
| PP-OCRv5 det+cls+rec is **21,848,679 bytes** total | downloaded and hashed 2026-09-08 | `models.json` |
| 106 tests pass on Linux with no device and no models | `flutter test` + `dart test` | CI |

---

## The seventh technical challenge (plan §13.5) — it exists, and it is ours

You asked for one nobody else would raise, that only comes from touching the
code. This is it, and it is better than the fallback candidate the plan
suggested because it is a *finding*, verifiable in one command by the reviewer.

> **The dependency that makes an F-Droid build impossible is invisible from
> Dart.** The plan for capture was to build on `doclens`, the one MIT Flutter
> plugin that already exposes a live document quad. Reading its Gradle file
> shows two unconditional `com.google.android.gms:play-services-mlkit-*`
> dependencies, used by exactly three of its files — the optional native-UI
> scanner and two text helpers. Because Gradle resolves `implementation`
> dependencies unconditionally, every application that adds `doclens` links
> Play Services into its APK whether or not it ever calls those paths, and is
> therefore unshippable on F-Droid and broken on de-Googled devices. The Dart
> API gives no hint of this.
>
> This is not a one-package accident. It is what the Android ecosystem looks
> like from below: the convenient building blocks quietly assume Google's
> runtime, and a project whose premise is technological sovereignty discovers
> it one Gradle file at a time. The consequence for this project is concrete —
> `byrsa_capture` carries its own CameraX detector, and the difference is
> asserted in CI rather than promised. The patch that would make `doclens`
> usable is written and ready to file.

Second finding, if a second is ever useful: **pub.dev refuses packages with git
dependencies**, and `mobile_ocr` — the only maintained Play-Services-free
cross-platform OCR plugin for Flutter — is not published there. So no package
can be built on top of it and published. That caps how far good work travels,
and it is fixable with four small files.

Both findings are the same finding, which is worth saying out loud in the
application because it *is* the project's thesis from §1: the free ecosystem's
building blocks are individually good and collectively uncomposable, and the
reasons are boring — one line in a Gradle file, one `pub publish` nobody ran.
Fixing them is not a detour from Byrsa. It is Byrsa's premise demonstrated on
the two packages closest to it.

---

## Upstream contributions (plan §13.3, §12/S6)

Two are written in full and ready to post. Filing them is a five-minute job you
should do before week 6, and the links then go straight into the *Comparison*
field.

- [`docs/upstream/doclens-play-services.md`](upstream/doclens-play-services.md)
  — with a reproduction recipe and three concrete fixes offered.
- [`docs/upstream/mobile-ocr-pub-dev.md`](upstream/mobile-ocr-pub-dev.md) — with
  an offer to send the pull request.

---

## Corrections to the plan that the code forced

Recorded properly in `DECISIONS.md`; listed here because Annex A has to match.

1. **T1 does not build on `doclens`** (D-017). §4.1 said fork it; §0.1 said no
   Play Services, and §0 wins. The task description in the budget should say
   "own CameraX/AVFoundation implementation, with the ML Kit modularisation
   contributed upstream", not "builds on the existing doclens plugin".
2. **T2's quantisation is not an optimisation.** DocShadow at 120 MB fp32
   cannot ship at all unquantised. Say that in *Technical challenges*: it is
   more honest and more competent than "includes quantisation".
3. **T3 delegates rather than reimplements** (D-021), and the publishing
   blocker that came with that is gone: the API and the engine are separate
   packages, so `byrsa_ocr` is publishable today and the git dependency is
   quarantined in a binding package nobody needs to adopt (D-027). The
   milestone no longer waits on a third party's release calendar — which is a
   better answer for a reviewer than either "we are blocked" or "we forked it".
4. **The stack changed in two places** — no `opencv_dart` in the classical path
   (D-020), no drift (D-022) — both to protect application size and
   reproducible builds. Worth one sentence in the budget, because both are
   defensible and both show the size risk was taken seriously.

---

## Still only you can write these

| Field | What is missing |
|---|---|
| *What makes you the right person* | Everything. Two projects with links, your experience in the three hard areas, and what you have already done here — which is now a repository with real commits and measured claims. |
| Budget: rate and hours | The arithmetic template is in the plan. Ask about the rate at the office hour on 30 September (U-15). |
| Contact, PGP key | `gpg --full-generate-key`, five minutes. |
| The 50 documents | `harness/dataset/README.md` has the shot list. It is the one deliverable that depends on nothing compiling. |
