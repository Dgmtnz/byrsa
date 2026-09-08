// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

/// Writes PDFs whose pages carry a scanned image plus an **invisible text
/// layer**: the text is selectable, searchable and readable by screen readers,
/// while the page still looks exactly like the scan.
///
/// Pure Dart, no dependencies beyond `meta`, no platform channels. It runs in a
/// Flutter app, in a server and in a plain `dart test`.
library;

import 'dart:typed_data';

import 'src/geometry.dart';
import 'src/image.dart';
import 'src/text_layer.dart';
import 'src/writer.dart';

export 'src/geometry.dart' show PdfRect, PdfWord;
export 'src/image.dart' show PdfImage;
export 'src/text_layer.dart'
    show
        PlacedWord,
        encodeWinAnsi,
        kMaxHorizontalScale,
        kMinHorizontalScale,
        kUnencodableByte,
        placeWord;

/// One page: a scan, and the words the OCR engine found in it.
class SearchablePage {
  SearchablePage({
    required this.image,
    this.words = const <PdfWord>[],
    this.dpi = 300,
  }) : assert(dpi > 0, 'dpi must be positive');

  final PdfImage image;

  /// Words in **image pixel coordinates**, origin top-left.
  ///
  /// Order is preserved but not meaningful: viewers reconstruct reading order
  /// from geometry.
  final List<PdfWord> words;

  /// Resolution used to turn pixels into PDF points.
  ///
  /// The page ends up `image.width / dpi` inches wide. For a fixed paper size
  /// instead, pass the resolution that produces it — A4 portrait is
  /// `image.width / 8.27`.
  final double dpi;

  double get _pointsPerPixel => 72 / dpi;
  double get widthInPoints => image.width * _pointsPerPixel;
  double get heightInPoints => image.height * _pointsPerPixel;
}

/// Builds a searchable PDF from one or more [SearchablePage]s.
///
/// ```dart
/// final bytes = SearchablePdf(title: 'Invoice')
///     .addPage(SearchablePage(
///       image: PdfImage.decode(jpegBytes),
///       words: [PdfWord('Total', PdfRect(120, 900, 260, 940))],
///     ))
///     .build();
/// ```
class SearchablePdf {
  SearchablePdf({
    this.title,
    this.creationDate,
    this.debugVisibleText = false,
    this.onWarning,
  });

  /// Optional document title, written to the info dictionary.
  final String? title;

  /// Fixes the creation date. Pass one to make output byte-for-byte
  /// reproducible — which milestone M6 needs and F-Droid checks.
  final DateTime? creationDate;

  /// Draws the layer in red instead of invisibly.
  ///
  /// This exists because misaligned invisible text is the failure mode of this
  /// whole technique and it is invisible by construction. Turn it on, look at
  /// the page, turn it off.
  final bool debugVisibleText;

  /// Called for every lossy or suspicious decision, with a human-readable
  /// reason. Nothing is ever dropped silently.
  final void Function(String message)? onWarning;

  final List<SearchablePage> _pages = <SearchablePage>[];

  /// Adds a page. Returns `this` so calls can be chained.
  SearchablePdf addPage(SearchablePage page) {
    _pages.add(page);
    return this;
  }

  int get pageCount => _pages.length;

  /// Serialises the document.
  Uint8List build() {
    if (_pages.isEmpty) {
      throw StateError('A PDF needs at least one page.');
    }

    final writer = PdfWriter();
    final catalog = writer.reserve();
    final pageTree = writer.reserve();
    final font = writer.reserve();
    final info = writer.reserve();

    final pageObjects = <int>[];
    for (final page in _pages) {
      final pageObject = writer.reserve();
      final contentObject = writer.reserve();
      final imageObject = writer.reserve();
      pageObjects.add(pageObject);

      final placed = <PlacedWord>[];
      for (final word in page.words) {
        final p = placeWord(
          word,
          pointsPerPixel: 72 / page.dpi,
          imageHeightPx: page.image.height,
          onWarning: onWarning,
        );
        if (p != null) placed.add(p);
      }

      writer.writeObject(
        pageObject,
        '<< /Type /Page /Parent $pageTree 0 R '
        '/MediaBox [0 0 ${pdfNum(page.widthInPoints)} ${pdfNum(page.heightInPoints)}] '
        '/Resources << /XObject << /Im0 $imageObject 0 R >> '
        '/Font << /F0 $font 0 R >> >> '
        '/Contents $contentObject 0 R >>',
      );
      writer.writeStream(
        contentObject,
        '',
        pageContentStream(
          pageWidth: page.widthInPoints,
          pageHeight: page.heightInPoints,
          words: placed,
          debugVisibleText: debugVisibleText,
        ),
      );
      writer.writeStream(
        imageObject,
        imageDictionary(page.image),
        page.image.data,
      );
    }

    writer.writeObject(catalog, '<< /Type /Catalog /Pages $pageTree 0 R >>');
    writer.writeObject(
      pageTree,
      '<< /Type /Pages /Count ${pageObjects.length} '
      '/Kids [${pageObjects.map((n) => '$n 0 R').join(' ')}] >>',
    );
    writer.writeObject(
      font,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    );
    final titleEntry = title == null
        ? ''
        : '/Title ${pdfLiteralString(encodeWinAnsi(title!, onWarning: onWarning))} ';
    writer.writeObject(
      info,
      '<< $titleEntry/Producer (dart_searchable_pdf) '
      '/CreationDate (${pdfDate(creationDate ?? DateTime.now())}) >>',
    );

    return writer.finish(rootObject: catalog, infoObject: info);
  }
}
