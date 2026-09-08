// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

/// One document of the evaluation set.
///
/// The set is 50 real documents. That number is fixed, and it is the same
/// number in the plan, in milestone M2 and in the funding application.
class DatasetDocument {
  DatasetDocument({
    required this.id,
    required this.file,
    required this.groundTruth,
    required this.category,
    required this.language,
    required this.conditions,
    required this.publish,
    required this.license,
  });

  factory DatasetDocument.fromJson(Map<String, Object?> json) =>
      DatasetDocument(
        id: json['id']! as String,
        file: json['file']! as String,
        groundTruth: json['groundTruth']! as String,
        category: json['category'] as String? ?? 'unknown',
        language: json['language'] as String? ?? 'es',
        conditions:
            (json['conditions'] as List?)?.cast<String>() ?? const <String>[],
        publish: json['publish'] as bool? ?? false,
        license: json['license'] as String?,
      );

  final String id;

  /// Path to the photograph, relative to the dataset directory.
  final String file;

  /// Path to the transcription a human typed, relative to the dataset directory.
  final String groundTruth;

  /// receipt, invoice, book-page, id-card, whiteboard, ...
  final String category;

  /// BCP-47 language tag of the document's text.
  final String language;

  /// crumpled, low-light, hand-shadow, curved, glare, ...
  final List<String> conditions;

  /// Whether the image may be redistributed.
  ///
  /// Identity documents and personal invoices are annotated privately and
  /// published only as synthetic equivalents. The scoring works the same
  /// either way; what changes is what ships in the repository.
  final bool publish;

  final String? license;
}

/// The evaluation set, loaded from `dataset/manifest.json`.
class Dataset {
  Dataset(this.directory, this.documents);

  factory Dataset.load(Directory directory) {
    final file = File('${directory.path}/manifest.json');
    if (!file.existsSync()) {
      throw StateError(
        'No manifest at ${file.path}. See harness/README.md: the 50 documents '
        'are photographed by hand and are the most valuable asset here.',
      );
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final documents = (json['documents']! as List)
        .cast<Map<String, Object?>>()
        .map(DatasetDocument.fromJson)
        .toList();
    return Dataset(directory, documents);
  }

  final Directory directory;
  final List<DatasetDocument> documents;

  String groundTruthOf(DatasetDocument document) =>
      File('${directory.path}/${document.groundTruth}').readAsStringSync();

  Iterable<String> get categories =>
      documents.map((d) => d.category).toSet().toList()..sort();
}
