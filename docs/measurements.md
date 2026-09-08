<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# Measurements

Every number this project has measured, with the machine and the command that
produced it. Nothing here is an estimate; anything that would be an estimate
lives in [`UNVERIFIED.md`](../UNVERIFIED.md) instead.

The rule, from `CONTRIBUTING.md`: a number that does not say which platform it
was measured on is not a number.

---

## 2026-09-08 — first session

**Machine:** Linux x86-64 (CachyOS), Flutter 3.47.2, Dart 3.13.2, Android SDK
36, JDK 25. **No Android device and no macOS machine were involved**, so
nothing below is a runtime measurement on a phone.

### Build composition

| What | Value | Command |
|---|---|---|
| `com.google.android.gms` / `com.google.mlkit` classes in the application's debug APK | **0** | `tool/check_no_play_services.sh app/build/app/outputs/flutter-apk/app-debug.apk` |
| `androidx.camera` references in the same APK | 1717 | same |
| `libonnxruntime.so`, arm64-v8a, as shipped by `mobile_ocr` | **27,985,944 bytes** | `unzip -l` on the APK |
| `libonnxruntime.so`, armeabi-v7a | 20,008,548 bytes | same |
| Debug APK, all ABIs, unshrunk | 233 MB | `du -h` |

The debug figure is not a release figure and must not be quoted as one. What it
does establish is where the weight is: ONNX Runtime's native library is ~28 MB
per 64-bit ABI before a single model is downloaded, which is the dominant term
in the application-size risk.

### Model sizes and digests

Downloaded and hashed on 2026-09-08 with `dart run tool/pin_models.dart`. Full
digests are in [`models.json`](../models.json).

| Model | Bytes | Licence |
|---|---|---|
| UVDoc (dewarping), ONNX | 31,684,150 | Apache-2.0 |
| DocShadow-SD7K (shadow removal), ONNX fp32 | **120,041,674** | MIT |
| PP-OCRv5 detector | 4,748,769 | UNAUDITED |
| PP-OCRv5 classifier | 582,663 | UNAUDITED |
| PP-OCRv5 recogniser | 16,517,247 | UNAUDITED |

**The DocShadow figure changes the plan.** At 120 MB it is four times UVDoc and
cannot ship in any form at all without quantisation. Quantisation is therefore
not an optimisation inside T2, it is the precondition for the task, and whether
the model survives int8 with its quality intact is an open question this
project will answer with the harness rather than with adjectives.

### Test suite

| What | Value |
|---|---|
| Tests passing, no device, no models, no network | **106** |
| `flutter analyze` across the workspace | 0 issues |
| `reuse lint` | 377 / 377 files compliant |
| `dart format --set-exit-if-changed` | clean |

Breakdown: `dart_searchable_pdf` 30 (including Poppler round-trips),
`byrsa_capture` 28, `byrsa_restore` 19, `byrsa_ocr` 10, `byrsa` (app) 19,
`harness` 9.

### Correctness properties asserted, not just exercised

These are the assertions worth naming, because they are the failure modes the
plan predicted:

- **Invisible-layer alignment.** Rendered word width equals the OCR box width,
  for narrow (`i`), wide (`WWWW`) and accented (`Facturación`) words, at three
  box sizes. This is the §4.5 trap.
- **Reproducible PDF bytes.** Same input and a fixed creation date produce
  identical output.
- **Aspect-ratio recovery.** A synthetic pinhole camera projects a known A4
  sheet at 30°, and the closed form recovers 210/297 to within 1%, beating the
  visible-sides average. It returns `null` for a single-axis tilt, where the
  answer is genuinely undetermined.
- **Auto-capture refuses a blurred frame** even when the scene is steady.
- **A stage that cannot run is recorded, not hidden**, and a stage that throws
  costs its stage rather than the capture.
- **Search survives characters that are FTS5 syntax**: a stray `"` or `*`
  returns no results instead of an error.
- **A model whose digest does not match is deleted**, and an unpinned model is
  refused outright.

### Not measured, and not claimed

No frame rate. No inference time. No CER. No memory. No iOS anything. Those
need hardware and the fifty-document set, and they are listed with their
commands in [`UNVERIFIED.md`](../UNVERIFIED.md).
