// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:meta/meta.dart';

/// One file of a model.
///
/// A model is not always one file. ONNX stores weights over about 2 GB — and,
/// as it turns out, plenty of smaller ones — in an external `.data` sidecar
/// that the `.onnx` references **by file name**. So the name is part of the
/// contract: rename the sidecar and the model stops loading, with an error
/// that does not mention the renaming.
@immutable
class ModelFile {
  const ModelFile({
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    this.sha256,
  });

  factory ModelFile.fromJson(Map<String, Object?> json) => ModelFile(
        fileName: json['fileName']! as String,
        url: json['url']! as String,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String?,
      );

  /// The exact name this file must have on disk.
  final String fileName;
  final String url;
  final int sizeBytes;

  /// Lowercase hex digest, or null when nobody has pinned it yet.
  final String? sha256;

  bool get isPinned => sha256 != null && sha256!.length == 64;
}

/// One downloadable model.
///
/// Every field here exists because something in the project needs it to be
/// checkable by a person: the licence because each model has to be audited
/// separately, the digest because a downloaded blob nobody verified is a
/// supply-chain hole, the size because the user is told what they are about to
/// spend before the download starts.
@immutable
class ModelDescriptor {
  const ModelDescriptor({
    required this.id,
    required this.files,
    required this.license,
    this.description,
    this.source,
    this.usable = true,
    this.notUsableReason,
  });

  factory ModelDescriptor.fromJson(Map<String, Object?> json) {
    final rawFiles = json['files'] as List?;
    return ModelDescriptor(
      id: json['id']! as String,
      files: rawFiles == null
          // A single-file model may be written the short way.
          ? <ModelFile>[
              ModelFile(
                fileName: json['fileName'] as String? ?? '${json['id']}.onnx',
                url: json['url']! as String,
                sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
                sha256: json['sha256'] as String?,
              ),
            ]
          : rawFiles
              .cast<Map<String, Object?>>()
              .map(ModelFile.fromJson)
              .toList(growable: false),
      license: json['license'] as String? ?? 'UNAUDITED',
      description: json['description'] as String?,
      source: json['source'] as String?,
      usable: json['usable'] as bool? ?? true,
      notUsableReason: json['notUsableReason'] as String?,
    );
  }

  final String id;

  /// Every file, in order. The first is the one an inference session opens.
  final List<ModelFile> files;

  /// SPDX identifier, or `UNAUDITED` until a human has read the model card.
  final String license;

  final String? description;

  /// Where the model came from, so the pin can be re-derived.
  final String? source;

  /// Whether this model should be shipped at all.
  ///
  /// Kept in the manifest rather than deleted, because "we measured this and
  /// rejected it" is more useful to the next person than an absence.
  final bool usable;
  final String? notUsableReason;

  ModelFile get primary => files.first;

  int get sizeBytes => files.fold(0, (total, file) => total + file.sizeBytes);

  bool get isPinned => files.every((file) => file.isPinned);
  bool get isLicenseAudited => license != 'UNAUDITED';
}

/// The set of models the application knows how to fetch.
class ModelCatalog {
  const ModelCatalog(this.models);

  /// Parses the repository's `models.json`.
  factory ModelCatalog.parse(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    return ModelCatalog(<String, ModelDescriptor>{
      for (final entry
          in (json['models']! as List).cast<Map<String, Object?>>())
        entry['id']! as String: ModelDescriptor.fromJson(entry),
    });
  }

  final Map<String, ModelDescriptor> models;

  ModelDescriptor operator [](String id) {
    final model = models[id];
    if (model == null) {
      throw ArgumentError(
        'No model "$id" in the catalogue. Known: ${models.keys.join(", ")}',
      );
    }
    return model;
  }

  /// Models that may not be shipped yet: an unpinned digest, an unaudited
  /// licence, or one we measured and rejected.
  ///
  /// A build that would distribute one of these makes a claim the project
  /// cannot back, so there is a test that this list is empty before a release.
  List<ModelDescriptor> get blockers => models.values
      .where((m) => !m.isPinned || !m.isLicenseAudited || !m.usable)
      .toList(growable: false);
}
