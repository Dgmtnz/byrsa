// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// The part of `byrsa_restore` that runs anywhere, including in a browser.
///
/// Everything here depends on nothing but `dart:math`, `dart:typed_data` and
/// `package:meta`: the classical restoration, the dewarp, the intrusion
/// removal, the pipeline that sequences them and the buffer they all operate
/// on. No file system, no platform channels, no native library.
///
/// The main `byrsa_restore.dart` entry point additionally exports [ModelStore],
/// which downloads model files and therefore needs `dart:io`. That single
/// import is enough to stop the whole package compiling for the web, and it
/// cannot be stubbed honestly — `install` returns a `File`, and a browser has
/// nowhere to put one.
///
/// So the split is by capability rather than by taste: import this entry point
/// where there is no disk, and the full one where there is. The restoration
/// code is identical either way, which is the point — a demo in a browser runs
/// the same arithmetic as the phone.
library;

export 'src/classical.dart' show ClassicalRestore, PageFilter;
export 'src/dewarp.dart';
export 'src/image_buffer.dart';
export 'src/intrusion.dart';
export 'src/model_catalog.dart';
export 'src/pipeline.dart';
