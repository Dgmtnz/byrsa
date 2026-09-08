// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:meta/meta.dart';

/// A folder in the library. Folders nest.
@immutable
class Folder {
  const Folder({required this.id, required this.name, this.parentId});

  final int id;
  final String name;
  final int? parentId;
}

/// One recognised word and where it sits on the page, in image pixels.
///
/// Stored alongside the text because a searchable PDF needs a box per word.
/// Text alone gives you search inside the application and an image-only PDF
/// outside it, which is half the promise.
@immutable
class PageWord {
  const PageWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory PageWord.fromJson(Map<String, Object?> json) => PageWord(
        text: json['t']! as String,
        left: (json['l']! as num).toDouble(),
        top: (json['o']! as num).toDouble(),
        right: (json['r']! as num).toDouble(),
        bottom: (json['b']! as num).toDouble(),
      );

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Short keys on purpose: a dense page is a few thousand words, and this is
  /// stored once per page in the database.
  Map<String, Object?> toJson() => <String, Object?>{
        't': text,
        'l': left,
        'o': top,
        'r': right,
        'b': bottom,
      };
}

/// One page of a document.
@immutable
class ScanPage {
  const ScanPage({
    required this.id,
    required this.documentId,
    required this.position,
    required this.originalPath,
    this.processedPath,
    this.text,
    this.words = const <PageWord>[],
    this.width,
    this.height,
  });

  final int id;
  final int documentId;

  /// Zero-based order within the document.
  final int position;

  /// The frame as the camera produced it.
  ///
  /// Kept forever, and every reprocessing starts from it. Re-warping or
  /// re-restoring an already processed page compounds the artefacts of both.
  final String originalPath;

  /// The rectified and restored page, when it exists.
  final String? processedPath;

  /// Recognised text, if OCR has run.
  final String? text;

  /// Word boxes, if OCR has run. Empty when the page was recognised by an
  /// older version that only kept the text.
  final List<PageWord> words;

  final int? width;
  final int? height;

  String get displayPath => processedPath ?? originalPath;
  bool get hasText => (text ?? '').trim().isNotEmpty;

  /// Whether this page can produce a genuinely searchable PDF page.
  bool get hasWordBoxes => words.isNotEmpty;

  ScanPage copyWith({
    String? processedPath,
    String? text,
    List<PageWord>? words,
    int? position,
  }) =>
      ScanPage(
        id: id,
        documentId: documentId,
        position: position ?? this.position,
        originalPath: originalPath,
        processedPath: processedPath ?? this.processedPath,
        text: text ?? this.text,
        words: words ?? this.words,
        width: width,
        height: height,
      );
}

/// A scanned document: an ordered set of pages, in a folder.
@immutable
class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.pages = const <ScanPage>[],
  });

  final int id;
  final String title;
  final int? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScanPage> pages;

  int get pageCount => pages.length;
  bool get isSearchable => pages.any((p) => p.hasText);

  /// The whole document as text, pages separated by a blank line.
  String get text => pages.map((p) => p.text ?? '').join('\n\n').trim();
}

/// A search hit, with the snippet that matched.
@immutable
class SearchHit {
  const SearchHit({
    required this.documentId,
    required this.title,
    required this.snippet,
    required this.pagePosition,
  });

  final int documentId;
  final String title;

  /// Text around the match, with the matched terms marked by `[` and `]`.
  final String snippet;

  final int pagePosition;
}
