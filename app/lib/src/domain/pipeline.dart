// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';

/// Turns one captured frame into a restored image and recognised text, and a
/// whole document into a searchable PDF.
///
/// Every dependency is injected as a function, so the whole pipeline runs in a
/// unit test on Linux with no camera, no models and no device. That is not a
/// testing nicety: it is the only way this project has any coverage at all
/// while iOS cannot be measured and Android needs hardware.
class DocumentPipeline {
  const DocumentPipeline({
    required this.restore,
    required this.recognise,
    required this.readImage,
    required this.writeImage,
  });

  /// Restoration stages, in order.
  final RestorePipeline restore;

  /// OCR. Null disables it, which is what happens when the user has not
  /// downloaded the models.
  final Future<OcrResult> Function(String imagePath)? recognise;

  /// Decodes a file into a buffer the restoration can work on.
  final Future<ImageBuffer> Function(String path) readImage;

  /// Encodes a buffer back to a file and returns its path.
  final Future<String> Function(ImageBuffer image, String path) writeImage;

  /// Processes one page.
  ///
  /// Always reads [originalPath] — never a previously processed file — so
  /// re-running after a settings change does not stack artefacts.
  Future<PageResult> processPage({
    required String originalPath,
    required String outputPath,
  }) async {
    final stages = <StageOutcome>[];

    final decodeWatch = Stopwatch()..start();
    final input = await readImage(originalPath);
    stages.add(StageOutcome(id: 'decode', duration: decodeWatch.elapsed));

    final restored = await restore.run(input);
    stages.addAll(restored.outcomes);

    final encodeWatch = Stopwatch()..start();
    final processedPath = await writeImage(restored.image, outputPath);
    stages.add(StageOutcome(id: 'encode', duration: encodeWatch.elapsed));

    OcrResult? ocr;
    if (recognise == null) {
      stages.add(StageOutcome(
        id: 'ocr',
        duration: Duration.zero,
        skipReason: StageSkipReason.disabledByUser,
      ));
    } else {
      final watch = Stopwatch()..start();
      try {
        ocr = await recognise!(processedPath);
        stages.add(StageOutcome(id: 'ocr', duration: watch.elapsed));
      } on Object catch (error) {
        stages.add(StageOutcome(
          id: 'ocr',
          duration: watch.elapsed,
          skipReason: StageSkipReason.failed,
          error: error,
        ));
      }
    }

    return PageResult(
      processedPath: processedPath,
      width: restored.image.width,
      height: restored.image.height,
      ocr: ocr,
      stages: stages,
    );
  }

  /// Builds a searchable PDF from processed pages.
  ///
  /// The invisible text layer is what makes a scan findable later, and it is
  /// the difference between an archive and a pile of photographs.
  static Uint8List buildPdf(
    List<PdfPageInput> pages, {
    String? title,
    DateTime? creationDate,
    void Function(String warning)? onWarning,
  }) {
    final pdf = SearchablePdf(
      title: title,
      creationDate: creationDate,
      onWarning: onWarning,
    );
    for (final page in pages) {
      pdf.addPage(SearchablePage(
        image: PdfImage.decode(page.imageBytes),
        words: <PdfWord>[
          for (final word in page.words)
            PdfWord(
              word.text,
              PdfRect(
                  word.box.left, word.box.top, word.box.right, word.box.bottom),
            ),
        ],
        dpi: page.dpi,
      ));
    }
    return pdf.build();
  }
}

/// What one page produced.
class PageResult {
  const PageResult({
    required this.processedPath,
    required this.width,
    required this.height,
    required this.stages,
    this.ocr,
  });

  final String processedPath;
  final int width;
  final int height;
  final OcrResult? ocr;
  final List<StageOutcome> stages;

  String get text => ocr?.text ?? '';

  Duration get total =>
      stages.fold(Duration.zero, (sum, stage) => sum + stage.duration);

  /// Shaped for the evaluation harness's run file, so a real run on a real
  /// phone produces a file the published benchmark can score directly.
  Map<String, Object?> toHarnessJson(String documentId, {int? outputBytes}) =>
      <String, Object?>{
        'id': documentId,
        'text': text,
        if (outputBytes != null) 'outputBytes': outputBytes,
        'stages': stages.map((s) => s.toJson()).toList(),
      };
}

/// One page on its way into a PDF.
class PdfPageInput {
  const PdfPageInput({
    required this.imageBytes,
    required this.words,
    this.dpi = 300,
  });

  final Uint8List imageBytes;
  final List<OcrWord> words;
  final double dpi;
}
