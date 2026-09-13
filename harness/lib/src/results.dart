// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

/// Timing and memory for one pipeline stage on one document.
class StageMeasurement {
  StageMeasurement({
    required this.name,
    required this.milliseconds,
    this.peakMemoryBytes,
    this.skipped = false,
    this.skipReason,
  });

  factory StageMeasurement.fromJson(Map<String, Object?> json) =>
      StageMeasurement(
        name: json['name']! as String,
        milliseconds: (json['milliseconds'] as num?)?.toDouble() ?? 0,
        peakMemoryBytes: (json['peakMemoryBytes'] as num?)?.toInt(),
        skipped: json['skipped'] as bool? ?? false,
        skipReason: json['skipReason'] as String?,
      );

  final String name;
  final double milliseconds;
  final int? peakMemoryBytes;

  /// A stage that could not run — no model downloaded, platform without
  /// support — is recorded, not hidden. See DECISIONS.md D-016.
  final bool skipped;
  final String? skipReason;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'milliseconds': milliseconds,
        if (peakMemoryBytes != null) 'peakMemoryBytes': peakMemoryBytes,
        if (skipped) 'skipped': true,
        if (skipReason != null) 'skipReason': skipReason,
      };
}

/// What the pipeline produced for one document.
class DocumentResult {
  DocumentResult({
    required this.id,
    required this.text,
    required this.stages,
    this.outputBytes,
    this.psnr,
    this.psnrInput,
  });

  factory DocumentResult.fromJson(Map<String, Object?> json) => DocumentResult(
        id: json['id']! as String,
        text: json['text'] as String? ?? '',
        stages: (json['stages'] as List? ?? const [])
            .cast<Map<String, Object?>>()
            .map(StageMeasurement.fromJson)
            .toList(),
        outputBytes: (json['outputBytes'] as num?)?.toInt(),
        psnr: (json['psnr'] as num?)?.toDouble(),
        psnrInput: (json['psnrInput'] as num?)?.toDouble(),
      );

  final String id;
  final String text;
  final List<StageMeasurement> stages;
  final int? outputBytes;

  /// Peak signal-to-noise ratio against a clean reference image, in dB.
  ///
  /// Only exists for synthetic documents, because only they have a clean
  /// original to compare against. A real photograph has no ground truth for
  /// its own pixels, which is why the headline metric over the fifty documents
  /// is character error rate and not this.
  final double? psnr;

  /// The same measurement on the untouched capture.
  ///
  /// Without it the restored figure is uninterpretable. Contrast-limited
  /// equalisation deliberately moves the image away from the clean original —
  /// it makes text darker and paper whiter than the page ever was — so it costs
  /// PSNR while improving readability. What means something is the distance
  /// travelled, not the absolute score, and that is why both ends are recorded.
  final double? psnrInput;

  /// How much the pipeline improved the page, in dB.
  double? get psnrGain =>
      (psnr == null || psnrInput == null) ? null : psnr! - psnrInput!;

  double get totalMilliseconds =>
      stages.fold(0, (sum, stage) => sum + stage.milliseconds);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'stages': stages.map((s) => s.toJson()).toList(),
        if (outputBytes != null) 'outputBytes': outputBytes,
        if (psnr != null) 'psnr': psnr,
        if (psnrInput != null) 'psnrInput': psnrInput,
      };
}

/// One run of the pipeline over the set, on one device.
///
/// Runs are produced on a device and scored here, so scoring works on a Linux
/// CI today and on a phone later without two implementations of the maths.
/// See DECISIONS.md D-019.
class RunResults {
  RunResults({
    required this.runId,
    required this.device,
    required this.platform,
    required this.pipeline,
    required this.documents,
    this.build,
    this.startedAt,
    this.notes,
  });

  factory RunResults.load(File file) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final run = json['run']! as Map<String, Object?>;
    return RunResults(
      runId: run['id']! as String,
      device: run['device']! as String,
      platform: run['platform']! as String,
      build: run['build'] as String?,
      startedAt: run['startedAt'] as String?,
      notes: run['notes'] as String?,
      pipeline: (run['pipeline'] as List? ?? const []).cast<String>(),
      documents: (json['documents']! as List)
          .cast<Map<String, Object?>>()
          .map(DocumentResult.fromJson)
          .toList(),
    );
  }

  final String runId;

  /// Free text, but be specific: "Pixel 6a, Android 14" beats "phone".
  final String device;

  /// android, ios, linux. The platform a number was measured on is part of the
  /// number, and every report prints it.
  final String platform;

  final String? build;
  final String? startedAt;
  final String? notes;
  final List<String> pipeline;
  final List<DocumentResult> documents;

  /// Writes the file `score` reads.
  ///
  /// A run used to be something only a device could produce, which meant the
  /// pipeline had never been executed over a corpus at all. It can be written
  /// from anywhere now; what the report never omits is which platform and
  /// which device produced it.
  Map<String, Object?> toJson() => <String, Object?>{
        'run': <String, Object?>{
          'id': runId,
          'device': device,
          'platform': platform,
          if (build != null) 'build': build,
          if (startedAt != null) 'startedAt': startedAt,
          if (notes != null) 'notes': notes,
          'pipeline': pipeline,
        },
        'documents': documents.map((d) => d.toJson()).toList(),
      };

  Map<String, DocumentResult> get byId =>
      <String, DocumentResult>{for (final d in documents) d.id: d};
}
