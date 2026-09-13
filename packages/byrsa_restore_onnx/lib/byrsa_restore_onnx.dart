// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// The neural half of [byrsa_restore], kept apart from the rest.
///
/// ONNX Runtime arrives as a Flutter plugin with native libraries attached, and
/// anything that depends on it inherits Flutter, a platform channel and — as
/// D-037 records — a native library collision that only appears in release
/// builds. `byrsa_restore` holds the image processing and stays pure Dart, so
/// it runs in a command-line harness, on a server, and under `dart test`.
///
/// This package holds the part that cannot.
library;

export 'src/uvdoc_stage.dart';
