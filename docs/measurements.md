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

### Release size — the answer to a risk the plan rated High

Updated 2026-09-09: **48.8 MB on arm64-v8a**, still with no model downloaded.

The 48.0 MB figure below is from the day before and is *not* a clean baseline
for the ONNX work — `image`, `image_picker` and `share_plus` also arrived in
between, so the 0.8 MB difference cannot be attributed to any one of them. What
can be said from the APK's contents rather than by subtraction: the second ONNX
Runtime binding contributes **no native library of its own**, because its copy
is excluded and it shares the one the OCR engine already brought.


`flutter build apk --release --split-per-abi`, on the full application: capture,
restoration, OCR with ONNX Runtime, and the searchable-PDF writer.

| ABI | Size |
|---|---|
| `armeabi-v7a` | **37.4 MB** |
| `arm64-v8a` | **48.0 MB** |
| `x86_64` | 55.4 MB |

That is the whole application **before any model is downloaded**, and the same
`arm64-v8a` APK still contains zero Play Services classes after R8 shrinking.

The plan listed "application size over 150 MB" as a high-probability risk. With
per-ABI splits it is not close: the phone a user actually installs on takes
48 MB, and the optional models add 31 MB (UVDoc) or about 22 MB (PP-OCR) only
when the user asks for them. The dominant term is ONNX Runtime's own native
library at ~28 MB for arm64, which is the price of doing inference without
Google Play Services and is worth stating as such.

The debug figure above is not a release figure and must not be quoted as one.

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

## 2026-09-09 — the restoration was unusable, and now is not

Same machine. The first version of `ClassicalRestore` analysed the image at full
resolution; the current one analyses a downscaled copy and applies the
correction in one fused integer pass (DECISIONS.md D-029).

| Image | Before | After | |
|---|---|---|---|
| 0.8 MP grayscale | 1,075 ms | 161 ms | |
| 3 MP grayscale | 2,336 ms | 228 ms | |
| **12 MP grayscale** | **55,921 ms** | **608 ms** | 92× |
| 12 MP colour | — | 907 ms | |

The shape matters as much as the number. The old cost grew with the blur
radius, and the radius grew with the image, so fifteen times the pixels cost
fifty-two times the time. The new cost is linear: 51 ms per megapixel at 12 MP,
against 215 ms per megapixel at 0.8 MP where fixed analysis cost still
dominates.

The analysis grid is a knob, and it behaves like one:

| `analysisWidth` | 12 MP grayscale |
|---|---|
| 256 | 383 ms |
| 512 (default) | 430 ms |
| 1024 | 721 ms |
| 2048 | 2,595 ms |

### What one page costs end to end

The path the application actually runs, with the 3000 px cap applied — a 6.8 MP
colour page:

| Stage | Time |
|---|---|
| Decode (`dart:ui`, platform codec) | not separately measured; a pure-Dart JPEG decode of the same size is 1,154 ms, which is why it is not used |
| Restore | 755 ms |
| JPEG encode (pure Dart) | 904 ms |
| **Total** | **~1.7 s** |

Encoding was the largest single term, so it now goes through the platform's own
encoder — `Bitmap.compress` on Android, `UIImage.jpegData` on iOS — via a
channel the application owns (DECISIONS.md D-038). The Dart encoder remains as
a real fallback, and the pipeline records which one ran, as `encode:native` or
`encode:dart`.

**How fast the native path actually is has not been measured**, because that
needs a device. What is measured is what it replaces: ~900 ms of pure Dart for
a 6.8 MP page. `UNVERIFIED.md` U-35.

All of this runs in an isolate, so it is a progress bar rather than a frozen
interface — a difference invisible in a benchmark and very visible in the hand.

**Not measured:** any of this on a phone. Expect several times slower, and do
not quote a multiplier until someone has run it (`UNVERIFIED.md`, U-31).

### Page filters, and a surprise in the encoder

A 6.8 MP colour page, the size the application actually processes:

| Filter | Restore | Encode | Total |
|---|---|---|---|
| Colour | 616 ms | 767 ms | 1,383 ms |
| Grayscale | 399 ms | 652 ms | 1,051 ms |
| Black and white | 462 ms | 581 ms | 1,043 ms |

Measured while adding them: handing `package:image`'s JPEG encoder a
**single-channel** buffer still produces a three-component JPEG, and a file
**twice the size** — 691 KB against 349 KB for the same pixels expanded to RGB
first. So grayscale pages are expanded before encoding. One extra pass, flat
chroma, and JPEG compresses that to almost nothing.

File sizes are not reported here because the test pages are synthetic and JPEG
size is entirely a function of content. That number needs the fifty real
documents.

## 2026-09-09 — the ONNX spike on Android

The plan calls ONNX its biggest risk. Most of that risk is about iOS, which
cannot be touched here. This is what Android and a desktop CPU could answer.

### The export the plan named cannot be used on a phone

`PaddlePaddle/UVDoc_onnx` takes `[N,3,H,W]` with dynamic spatial dimensions and
returns `[N,3,H',W']` — **three channels, so a rectified image**. That is
exactly the ambiguity plan §4.2 warned about. Run under `onnxruntime` on CPU
with four threads:

| Input | Time | Peak RSS |
|---|---|---|
| 712×488 (0.3 MP) | 188 ms | 144 MB |
| 1600×1200 (1.9 MP) | 258 ms | 209 MB |
| 2000×1500 (3.0 MP) | 312 ms | 289 MB |
| 3000×2250 (6.8 MP) | 487 ms | **477 MB** |

Time barely moves, because the network downscales internally — the plan said so
and it is true. Memory does move, because the output is an image the size of
the input, and the model can only give a page as large as the tensor it was
fed. A full-resolution page therefore costs 477 MB of peak memory, which on a
mid-range phone is not slow, it is an out-of-memory kill.

### The grid export can

`fredcallagan/uvdoc-grid-onnx`, Apache-2.0, 31.8 MB across two files: fixed
`[1,3,720,496]` input, `[1,2,45,31]` output in [-1, 1].

| | Time | Peak RSS |
|---|---|---|
| Grid export, any output resolution | **173 ms** | **127 MB** |

The resolution of the result is then decided in Dart, by `remapThroughGrid`,
which has ten tests. The sampling convention is taken from the original
authors' `bilinear_unwarping` — `align_corners=True` in both the grid upsample
and the sample — not guessed. The export's own `example.py` diverges from that
by upsampling with `cv2.resize`, which flattens half a grid cell at every edge;
the authors' code is the reference here.

### Two ONNX Runtimes collide, and only in release

`mobile_ocr` brings the Java AAR (`onnxruntime-android` 1.27.0, 28 MB per ABI);
`byrsa_restore` brings the Dart FFI package (its own build, 14 MB). Both ship a
file called `libonnxruntime.so`.

```
Execution failed for task ':app:mergeReleaseNativeLibs'.
> 2 files found with path 'lib/arm64-v8a/libonnxruntime.so'
```

**The debug build packages both without complaint. Only release fails** — so the
error arrives at the moment you try to ship.

And the obvious workaround is a trap. Adding `pickFirsts` makes it build, and
measured, it keeps the Dart package's 14.2 MB library and discards the AAR's
28 MB one:

| | Before the spike | With `pickFirsts` | Resolved deterministically |
|---|---|---|---|
| `arm64-v8a` release | 48.0 MB | 35.0 MB | **48.8 MB** |
| `armeabi-v7a` release | 37.4 MB | 28.1 MB | 38.3 MB |

The application got 13 MB smaller, which looks like a win and is the alarm.
`libonnxruntime4j_jni.so` — mobile_ocr's shim, compiled against 1.27.0 — is now
paired with a different, older runtime. An APK that got smaller is exactly how
that ships.

The choice is therefore made deterministically instead: the Dart package's
vendored copy is dropped at its source, so only the AAR's survives and both
bindings share ONNX Runtime 1.27.0. Asserted, not assumed: CI builds a release
APK and `tool/check_native_collisions.sh` reads the version string out of every
`libonnxruntime.so` in it, failing on anything but 1.27.0. Verified by
unzipping the release APK — the
27,985,944-byte library is the one present, paired with the JNI shim that was
built against it.

Which pairing is safer is a judgement, and it is worth stating: ONNX Runtime's
C API is versioned and backwards compatible, so an FFI binding generated
against an older header calling a newer library is the survivable direction. A
JNI shim built for 1.27.0 hunting for symbols in an older build is not.

### And the Dart ONNX package no longer builds in release at all

Behind the collision sits another release-only failure:

```
:onnxruntime:checkReleaseAarMetadata
> Dependency 'androidx.fragment:fragment:1.7.1' requires ... version 34 or later.
  :onnxruntime is currently compiled against android-33.
```

`onnxruntime_flutter` 1.4.1 pins `compileSdkVersion 33`. Worked around by
raising the subproject's compileSdk from the application's Gradle files —
which has to be registered before the `evaluationDependsOn(":app")` that
Flutter generates, because that one evaluates every plugin project and an
`afterEvaluate` registered afterwards never runs. The one-line real fix is
drafted in `docs/upstream/onnxruntime-flutter-compilesdk.md`.

## 2026-09-12 — DocShadow, and the first decision the dataset blocks

Plan §4.3 names DocShadow-SD7K and calls shadows "80% of the perceived effect".
Measured, it cannot be shipped — and the reason is arithmetic, not quality.

`image` `[batch, 3, height, width]` in, `result` `[batch, 3, height, width]`
out: an image the size of the input, the same shape that disqualified UVDoc's
image export. **10,612 nodes**, against 259 for the UVDoc grid.

| Input | Time | Peak RSS |
|---|---|---|
| loading the session | 2,606 ms | 338 MB |
| 256×256 (0.07 MP) | 251 ms | 344 MB |
| 384×512 (0.20 MP) | 689 ms | 368 MB |
| 576×768 (0.44 MP) | 1,854 ms | 430 MB |
| 768×1024 (0.79 MP) | **3,566 ms** | 534 MB |

The application processes 6.8 MP. Quantisation shrinks the weights, not the
operation count, so it does not close a gap of this size.

### The trick that works, and is not enough

Shadow removal is a low-frequency correction, like the paper-colour field in
D-029. Running the model small, taking the **ratio** of output to input as a
gain field, and applying that at full resolution costs 5× less and stays close
to the direct result: **27.0 dB** with analysis at 384×512, 697 ms against
3,597 ms. Good architecture, recorded for any future illumination model. It
still inherits the model's quality.

### Against the classical baseline

Synthetic 768×1024 page, PSNR against the un-shadowed original:

| | multiplicative shadow | physical shadow |
|---|---|---|
| untouched | 11.0 dB | 9.5 dB |
| **classical (already written)** | **25.7 dB** · 128 ms | **24.4 dB** · 124 ms |
| DocShadow direct | 17.0 dB · 3,445 ms | 18.5 dB · 3,165 ms |
| DocShadow gain field | 16.6 dB · 664 ms | 20.7 dB · 670 ms |
| gain field then classical | 20.5 dB · 792 ms | 23.0 dB · 794 ms |

The second column is built specifically to break the classical method's
assumption — additive ambient light, a blue tint and a wide penumbra, none of
which dividing by a background inverts. It still wins by 5.9 dB at a
twenty-fifth of the cost.

**What this does not show.** Both pages are synthetic, and DocShadow was
trained on real photographs; a model can score badly on synthetic data and well
on real. The test page is flat white paper with pure black text, which is an
unrealistically easy target for background division. And PSNR needs a clean
original, which the fifty real photographs will not have — the real benchmark
is CER.

So the conclusion splits. **Settled:** DocShadow-SD7K is not shipped; that is
architecture, not data. **Blocked:** whether any shadow network earns 120 MB.
Only the fifty photographs answer that, and it is the first engineering
decision that dataset gates rather than a marketing claim (`UNVERIFIED.md`
U-36).

### Test suite

| What | Value |
|---|---|
| Tests passing, no device, no models, no network | **163** |
| `flutter analyze` across the workspace | 0 issues |
| `reuse lint` | every file compliant |
| `dart format --set-exit-if-changed` | clean |

Breakdown: `dart_searchable_pdf` 30 (including Poppler round-trips),
`byrsa_capture` 33, `byrsa_restore` 44, `byrsa_ocr` 13, `byrsa_ocr_mobile_ocr`
6, `byrsa` (app) 37, `harness` 9.

`dart_searchable_pdf` and `byrsa_ocr` both pass `dart pub publish --dry-run`
with no warnings, and CI runs that check so a git dependency cannot creep back
into a publishable package without failing the build.

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
- **Auto-capture refuses a blurred frame** even when the scene is steady, and
  decides readiness in Dart rather than trusting the platform's hint — which is
  a bug this test caught: the native side only ever reports "moving", so a
  controller that passed the hint through would never fire at all.
- **A stage that cannot run is recorded, not hidden**, and a stage that throws
  costs its stage rather than the capture.
- **Search survives characters that are FTS5 syntax**: a stray `"` or `*`
  returns no results instead of an error.
- **A model whose digest does not match is deleted**, and an unpinned model is
  refused outright.
- **Restoration stays linear in pixels.** One test asserts that four times the
  pixels costs less than twelve times the time, which is the cheap way to catch
  a return to the quadratic behaviour that made the first version take a
  minute.
- **The analysis grid is a performance knob, not a quality one.** Changing it
  from 256 to 1024 moves the output by less than six grey levels on average.
- **A camera refusal is reported as a refusal**, with the permanent case told
  apart from the retryable one.
- **A kept scan survives the cache being emptied.** One test deletes the whole
  cache directory after saving and checks the file is still there — the data
  loss bug in a single assertion.
- **Text and word boxes are stored together.** A page with text but no boxes
  searches inside the application and exports an image-only PDF; the two states
  are distinguishable rather than inferred.

### Not measured, and not claimed

No frame rate. No inference time. No CER. No memory. No iOS anything. Those
need hardware and the fifty-document set, and they are listed with their
commands in [`UNVERIFIED.md`](../UNVERIFIED.md).
