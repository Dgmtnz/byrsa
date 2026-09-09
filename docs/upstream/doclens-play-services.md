<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# doclens: two pull requests to get Play Services out of the default build

**Repository:** `github.com/govindmaheshwari2/doclens`
**Version examined:** 0.0.9 (from pub.dev)
**Status:** draft, ready to file

---

## The shape of the proposal

Not "please make ML Kit optional" — that asks a maintainer to solve someone
else's problem. Two pull requests, and the first one is a gift: it **removes an
ML Kit dependency without removing a feature**.

| PR | What | Feature lost |
|---|---|---|
| 1 | Replace the text-orientation detector with a classical implementation | none |
| 2 | Move the two remaining ML Kit paths to `compileOnly`, opt-in at the app level | none by default; the native-UI scanner needs one line in the consumer's Gradle |

Before filing: check `doclens`'s `LICENSE` file, and confirm the iOS side uses
Vision/VisionKit rather than ML Kit — likely, but only the Kotlin was read.
(Repository rows U-27 and U-28.)

---

## The issue that precedes both

**Title:** ML Kit / Play Services is an unconditional dependency, which rules
the plugin out for F-Droid

`android/build.gradle.kts` declares, as plain `implementation` dependencies:

```kotlin
implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
```

Only three of the eleven Kotlin files use them:

- `NativeUIScanner.kt` — the optional OS-native scanner escape hatch
- `TextRecognizer.kt` — the optional OCR helper
- `TextOrientationDetector.kt` — used only by `AutoOrientation.auto`

The core of the plugin — `QuadDetector`, `ImageWarper`, `ScannerSession`,
`YuvUtils`, `ExifRotator`, `SharpnessEstimator`, the CameraX preview, the
Flutter UI — does not touch ML Kit at all.

Because Gradle resolves `implementation` dependencies unconditionally, **any
application that adds `doclens` links Play Services into its APK, even if it
never calls those three paths.** For a large class of Android users that is a
hard blocker rather than an inconvenience:

- **F-Droid's main repository** does not build applications that bundle
  proprietary libraries.
- The same applies to other independent distributions, and to de-Googled
  devices, where `GmsDocumentScanning` is not merely unused but absent — it is
  delivered by Play Services at runtime.

None of this is visible from the Dart side. It is one line in a Gradle file.

### Reproducing it

```bash
flutter create --template=app demo && cd demo
flutter pub add doclens
flutter build apk --debug
unzip -p build/app/outputs/flutter-apk/app-debug.apk 'classes*.dex' \
  | strings | grep -c 'com/google/android/gms'
```

A CameraX-only plugin returns `0` on the same check. We run exactly that
assertion in CI: [`tool/check_no_play_services.sh`](../../tool/check_no_play_services.sh).

---

## PR 1 — replace the orientation detector, drop a dependency for free

`TextOrientationDetector` runs ML Kit text recognition on a captured page and
uses the recognised text's direction to decide which way is up. That is a large
hammer: it pulls in a Play-Services-delivered model to answer a question that
does not need to read anything.

The same answer comes out of classical image statistics. Two approaches, either
adequate, both a few dozen lines over a downscaled grayscale image:

- **Projection profiles.** Binarise, then compute row and column sums at 0°,
  90°, 180° and 270°. Lines of text produce a strongly peaked profile
  perpendicular to the baseline; the orientation whose profile has the highest
  variance is the one where text lines are horizontal. Distinguishing 0° from
  180° then only needs the asymmetry of ascenders against descenders.
- **Gradient histograms.** Accumulate gradient directions; text produces a
  dominant axis perpendicular to the baseline.

Both work on any Android device, with no model, no download and no Play
Services, and both are testable on a laptop — which the current implementation
is not.

I am happy to write this, with unit tests against synthetic pages at the four
rotations.

## PR 2 — the two remaining paths become opt-in

`TextRecognizer` and `NativeUIScanner` genuinely need ML Kit. The smallest
change that keeps them working for the people who want them, and out of the APK
for everyone else:

- move the two ML Kit artifacts from `implementation` to `compileOnly`;
- guard each entry point with
  `Class.forName("com.google.mlkit.vision.text.TextRecognition")` and report the
  feature as unavailable when it is absent;
- document the two lines a consumer adds to `android/app/build.gradle.kts` to
  turn them back on, plus `-dontwarn com.google.mlkit.**` for R8.

Consumers who want the native scanner add a dependency; consumers who do not
get a clean build. The diff is small and no behaviour changes for anyone who
opts in.

### Alternatives considered, and why not

- **A product flavour.** Selecting a flavour of a plugin subproject means every
  consumer — and every F-Droid build recipe — needs a `missingDimensionStrategy`
  line. More moving parts than the problem deserves, and it fails in a confusing
  way when someone forgets.
- **A companion package** (`doclens_mlkit`). The cleanest boundary, and worth
  doing if you would rather. It is more churn for existing users, which is why
  it is second on this list rather than first.
- **Consumer-side `exclude group: 'com.google.android.gms'`.** Does not work:
  the plugin is built from source, so excluding the artifact breaks its own
  compilation. Supplying stub classes to make it compile anyway is a real
  technique and a bad idea — it produces a build that looks clean and fails at
  runtime, which is precisely what a distribution reviewer is right to
  distrust.

---

## Context

I am building a set of Apache-2.0 Flutter packages for document capture,
rectification and OCR, aimed at F-Droid and other independent distributions.
`doclens` was the intended foundation for the capture half, and the plan for the
project says in as many words: do not reimplement this, build on `doclens`.

Rather than fork, I would prefer to send these two patches and depend on the
plugin. In the meantime the project carries its own CameraX detector, and if
these land I would rather delete it and measure yours than maintain a parallel
implementation — a fork over two lines of Gradle is exactly the fragmentation
this ecosystem already has too much of.
