<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# doclens: make the ML Kit dependency optional

**Repository:** `github.com/govindmaheshwari2/doclens`
**Version examined:** 0.0.9 (from pub.dev)
**Status:** draft, ready to file

---

## Why this matters to Byrsa

The plan this project follows says, in as many words: do not reimplement edge
detection, build on `doclens`. That was the intention. This is why it did not
work as written, and what would make it work.

The finding also became the seventh technical challenge in the funding
application: a distribution problem that is invisible from the Dart side and
only shows up when you read a dependency's Gradle file.

---

## Issue text

**Title:** ML Kit / Play Services is an unconditional dependency, which rules
the plugin out for F-Droid

`android/build.gradle.kts` declares, as plain `implementation` dependencies:

```kotlin
implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
```

Only three files use them:

- `NativeUIScanner.kt` — the optional OS-native scanner escape hatch
- `TextRecognizer.kt` — the optional OCR helper
- `TextOrientationDetector.kt` — used only by `AutoOrientation.auto`

The core of the plugin — `QuadDetector`, `ImageWarper`, `ScannerSession`, the
CameraX preview, the Flutter UI — does not touch ML Kit at all.

Because Gradle resolves `implementation` dependencies unconditionally, **any
application that adds `doclens` links Play Services into its APK, even if it
never calls those three paths.** For a large class of Android users that is a
hard blocker rather than an inconvenience:

- **F-Droid** does not build applications that depend on proprietary Google
  libraries into their main flavour.
- The same applies to other independent distributions, and to de-Googled
  devices where Play Services is simply absent — `GmsDocumentScanning` is
  delivered by Play Services at runtime, so it also fails there.

This is a shame, because the interesting 90% of `doclens` is exactly the part
that has no such dependency.

### Suggested fix

Any of these would work, roughly in order of effort:

1. **A product flavour.** Move the three files into
   `android/src/mlkit/kotlin/...`, put the ML Kit dependencies in a
   `mlkitImplementation` configuration, and default the flavour on so existing
   users see no change. A consumer who needs a clean build selects the other
   flavour.
2. **`compileOnly` plus reflection.** Keep the sources, compile them against
   the ML Kit API without shipping it, and check
   `Class.forName("com.google.mlkit.vision.text.TextRecognition")` before use.
   Smallest diff; costs a runtime check.
3. **A companion package.** `doclens_mlkit` depends on `doclens` and adds the
   native-UI and text-recognition paths. Cleanest boundary, most churn for
   existing users.

I am happy to prepare the pull request for whichever you prefer — option 1 is
what I would write unless you say otherwise.

### How to reproduce

```bash
flutter create --template=app demo && cd demo
flutter pub add doclens
flutter build apk --debug
unzip -p build/app/outputs/flutter-apk/app-debug.apk 'classes*.dex' \
  | strings | grep -c 'com/google/android/gms'
```

For comparison, the same check against a CameraX-only plugin returns `0`. We
run exactly that assertion in CI:
[`tool/check_no_play_services.sh`](../../tool/check_no_play_services.sh).

### Context

I am building a set of Apache-2.0 Flutter packages for document capture,
rectification and OCR, aimed at F-Droid and other independent distributions,
and `doclens` was the intended foundation for the capture half. If the
dependency can be made optional, I would rather depend on `doclens` and
contribute to it than maintain a parallel detector.
