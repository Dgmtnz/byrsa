// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// On-device document restoration: shadow removal, illumination flattening and
/// geometric rectification.
///
/// Two tiers, and the package is honest about which one is running. The
/// **classical** tier is pure Dart, needs no download and works on any device.
/// The **neural** tier runs quantised ONNX models that the user opts into
/// downloading; when a model is missing or a platform cannot run it, the stage
/// reports itself as skipped instead of failing the pipeline.
library;

export 'src/classical.dart' show ClassicalRestore, PageFilter;
export 'src/dewarp.dart';
export 'src/image_buffer.dart';
export 'src/model_catalog.dart';
export 'src/model_store.dart';
export 'src/pipeline.dart';
