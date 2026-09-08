// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:meta/meta.dart';

/// One downloadable model.
///
/// Every field here exists because something in the project needs it to be
/// checkable by a person: the licence because each PaddleOCR model has to be
/// audited separately, the digest because a downloaded blob nobody verified is
/// a supply-chain hole, the size because the user is told what they are about
/// to spend before the download starts.
@immutable
class ModelDescriptor {
  const ModelDescriptor({
    required this.id,
    required this.url,
    required this.sizeBytes,
    required this.license,
    this.sha256,
    this.description,
    this.source,
  });

  factory ModelDescriptor.fromJson(Map<String, Object?> json) =>
      ModelDescriptor(
        id: json['id']! as String,
        url: json['url']! as String,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        license: json['license'] as String? ?? 'UNAUDITED',
        sha256: json['sha256'] as String?,
        description: json['description'] as String?,
        source: json['source'] as String?,
      );

  final String id;
  final String url;
  final int sizeBytes;

  /// SPDX identifier, or `UNAUDITED` until a human has read the model card.
  final String license;

  /// Lowercase hex digest of the file.
  ///
  /// Null means **nobody has pinned this model yet**. [ModelStore] refuses to
  /// install an unpinned model rather than trusting whatever the server sends,
  /// and the repository's `tool/pin_models.dart` fills the field in.
  final String? sha256;

  final String? description;

  /// Where the model came from, so the pin can be re-derived.
  final String? source;

  bool get isPinned => sha256 != null && sha256!.length == 64;
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
          'No model "$id" in the catalogue. Known: ${models.keys.join(", ")}');
    }
    return model;
  }

  /// Models that may not be shipped yet: unpinned digest, or unaudited licence.
  ///
  /// A build that would distribute one of these is a build that makes a claim
  /// the project cannot back, so there is a test that this list is empty before
  /// a release.
  List<ModelDescriptor> get blockers => models.values
      .where((m) => !m.isPinned || !m.isLicenseAudited)
      .toList(growable: false);
}
