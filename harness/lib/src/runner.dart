// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:image/image.dart' as img;

import 'dataset.dart';
import 'results.dart';
import 'synthetic.dart';

/// Runs the real restoration pipeline over a dataset and produces the run file
/// that `score` reads.
///
/// Until this existed, a run was something only a device could produce — which
/// meant the pipeline had never been executed over a corpus at all, and the
/// baseline milestone M2 is supposed to measure had no way to be measured.
///
/// It runs the same `ClassicalRestore` the application ships. Not a
/// reimplementation: a second copy of the maths would drift from the first, and
/// the number would quietly stop describing the product. That is the whole
/// reason `byrsa_restore` is pure Dart (DECISIONS.md D-040).
///
/// What it deliberately does not do is OCR. There is no engine in a
/// command-line program, so `text` comes back empty and character error rate is
/// left to a run produced on a device. A harness that invented a text field
/// would be worse than one that admits the gap.
class PipelineRunner {
  const PipelineRunner({
    this.filter = PageFilter.colour,
    this.analysisWidth = 512,
    this.jpegQuality = 92,
    this.writeOutput = true,
  });

  final PageFilter filter;
  final int analysisWidth;
  final int jpegQuality;

  /// Whether to keep the restored images. Off makes a timing run cheaper.
  final bool writeOutput;

  List<String> get pipeline =>
      <String>['decode', 'classical:${filter.name}', 'encode'];

  /// Processes every document and returns the results.
  ///
  /// [onDocument] is called after each one, for a progress line — a fifty-page
  /// run is minutes long and silence is indistinguishable from a hang.
  RunResults run(
    Dataset dataset, {
    required String runId,
    required String device,
    Directory? outputDirectory,
    void Function(int done, int total, String id)? onDocument,
  }) {
    final restore = ClassicalRestore(
      filter: filter,
      analysisWidth: analysisWidth,
    );
    outputDirectory?.createSync(recursive: true);

    final results = <DocumentResult>[];
    for (final (index, document) in dataset.documents.indexed) {
      results.add(
        _one(dataset, document, restore, outputDirectory),
      );
      onDocument?.call(index + 1, dataset.documents.length, document.id);
    }

    return RunResults(
      runId: runId,
      device: device,
      platform: Platform.operatingSystem,
      pipeline: pipeline,
      documents: results,
      startedAt: null,
      notes: 'Produced by `harness run`. No OCR engine: text is empty and '
          'character error rate is not measured here.',
    );
  }

  DocumentResult _one(
    Dataset dataset,
    DatasetDocument document,
    ClassicalRestore restore,
    Directory? outputDirectory,
  ) {
    final source = File('${dataset.directory.path}/${document.file}');
    if (!source.existsSync()) {
      return DocumentResult(
        id: document.id,
        text: '',
        stages: <StageMeasurement>[
          StageMeasurement(
            name: 'decode',
            milliseconds: 0,
            skipped: true,
            skipReason: 'missing file: ${document.file}',
          ),
        ],
      );
    }

    final watch = Stopwatch()..start();
    final decoded = img.decodeImage(source.readAsBytesSync());
    final decodeMs = watch.elapsedMicroseconds / 1000;
    if (decoded == null) {
      return DocumentResult(
        id: document.id,
        text: '',
        stages: <StageMeasurement>[
          StageMeasurement(
            name: 'decode',
            milliseconds: decodeMs,
            skipped: true,
            skipReason: 'not a readable image',
          ),
        ],
      );
    }

    final input = _toBuffer(decoded);
    final reference = _cleanReference(dataset, document);

    watch.reset();
    final restored = restore(input);
    final restoreMs = watch.elapsedMicroseconds / 1000;

    watch.reset();
    final encoded = img.encodeJpg(
      img.Image.fromBytes(
        width: restored.width,
        height: restored.height,
        bytes: _asRgb(restored).buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      ),
      quality: jpegQuality,
    );
    final encodeMs = watch.elapsedMicroseconds / 1000;

    if (writeOutput && outputDirectory != null) {
      File('${outputDirectory.path}/${document.id}.jpg')
          .writeAsBytesSync(encoded);
    }

    return DocumentResult(
      id: document.id,
      text: '',
      outputBytes: encoded.length,
      psnr: _against(reference, restored),
      psnrInput: _against(reference, input),
      stages: <StageMeasurement>[
        StageMeasurement(name: 'decode', milliseconds: decodeMs),
        StageMeasurement(
            name: 'classical:${filter.name}', milliseconds: restoreMs),
        StageMeasurement(name: 'encode', milliseconds: encodeMs),
      ],
    );
  }

  /// The clean original, where one exists.
  ///
  /// Only synthetic documents have one. A photograph of a page has no
  /// pixel-level ground truth for what the page "should" look like, which is
  /// why the metric over the real set is character error rate.
  ImageBuffer? _cleanReference(Dataset dataset, DatasetDocument document) {
    final path = document.groundTruthImage;
    if (path == null) return null;
    final file = File('${dataset.directory.path}/$path');
    if (!file.existsSync()) return null;
    final clean = img.decodeImage(file.readAsBytesSync());
    return clean == null ? null : _toBuffer(clean);
  }

  double? _against(ImageBuffer? reference, ImageBuffer image) {
    if (reference == null ||
        reference.width != image.width ||
        reference.height != image.height) {
      return null;
    }
    return psnr(_asRgb(reference), _asRgb(image));
  }

  static ImageBuffer _toBuffer(img.Image image) {
    final pixels = image.width * image.height;
    final rgb = Uint8List(pixels * 3);
    var i = 0;
    for (final pixel in image) {
      rgb[i * 3] = pixel.r.toInt();
      rgb[i * 3 + 1] = pixel.g.toInt();
      rgb[i * 3 + 2] = pixel.b.toInt();
      i++;
    }
    return ImageBuffer(
      width: image.width,
      height: image.height,
      channels: 3,
      data: rgb,
    );
  }

  /// Expands a grayscale result back to three channels.
  ///
  /// Measured in the application and true here too: a single-channel buffer
  /// still produces a three-component JPEG, and a file twice the size.
  static Uint8List _asRgb(ImageBuffer image) {
    if (!image.isGray) return image.data;
    final out = Uint8List(image.pixelCount * 3);
    for (var i = 0; i < image.pixelCount; i++) {
      final value = image.data[i];
      out[i * 3] = value;
      out[i * 3 + 1] = value;
      out[i * 3 + 2] = value;
    }
    return out;
  }
}
