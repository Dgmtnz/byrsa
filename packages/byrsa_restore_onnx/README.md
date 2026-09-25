<!--
SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
SPDX-License-Identifier: CC-BY-4.0
-->

# byrsa_restore_onnx

The neural stages of [`byrsa_restore`](../byrsa_restore): page dewarping with
UVDoc, through ONNX Runtime.

## This package exists to hold one dependency

ONNX Runtime arrives as a Flutter plugin with native libraries attached, and
everything that depends on it inherits Flutter, a platform channel, and — as
`DECISIONS.md` D-037 records — a native library collision that only appears in
release builds.

`byrsa_restore` holds the image processing and stays pure Dart, so it runs in a
command-line harness, on a server, and under `dart test`. That is not tidiness:
the evaluation harness measures the classical pipeline as the baseline every
neural stage has to beat, and it has to run *the same code the application
ships* rather than a reimplementation that drifts from it.

This package holds the part that cannot come along.

```dart
final pipeline = RestorePipeline(<RestoreStage>[
  UvdocStage(modelFile: File(modelPath)),   // skips itself if not downloaded
  const ClassicalStage(),
]);
```

## Status

| | |
|---|---|
| Compiles on Android | verified |
| Compiles on iOS | not verified — no macOS machine |
| Inference through this package, on a device | not verified — see `UNVERIFIED.md` U-34 |

The `.onnx` file itself has run, under Python on a desktop — see the class
documentation on `UvdocStage` for what that measured. But the pipeline records
no per-stage outcome, so nothing yet distinguishes this package's stage
running on a device from it being skipped.

The model is a 31.8 MB download the user starts explicitly. Until it is
present, the stage reports itself unavailable and the pipeline carries on — a
missing model is a skipped stage, never a failed scan.

## Licence

Apache-2.0. Part of [Byrsa](https://github.com/dgmtnz/byrsa).
