// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'cer.dart';
import 'dataset.dart';
import 'results.dart';

/// Score of one document in one run.
class DocumentScore {
  DocumentScore({
    required this.document,
    required this.cer,
    required this.wer,
    required this.milliseconds,
    required this.missing,
    this.outputBytes,
  });

  final DatasetDocument document;

  /// Null when no OCR ran at all, which is not the same as reading nothing.
  ///
  /// `harness run` has no OCR engine — the recogniser is a platform plugin, so
  /// a desktop run leaves `text` empty on purpose. Scoring an empty hypothesis
  /// against a real reference yields exactly 100%, and a table of 100% figures
  /// reads as a measured catastrophe rather than as "not measured". That is the
  /// same failure `psnr` avoids by returning null instead of infinity: a number
  /// nobody computed must not look like a number somebody computed.
  final ErrorRate? cer;
  final ErrorRate? wer;
  final double milliseconds;
  final int? outputBytes;

  /// The run produced nothing for this document. Counted as a total miss, not
  /// quietly dropped from the average — that is how benchmarks flatter
  /// themselves.
  final bool missing;
}

/// A full scoring of one run against the dataset.
class Scorecard {
  Scorecard({required this.run, required this.scores, required this.strict});

  final RunResults run;
  final List<DocumentScore> scores;
  final bool strict;

  /// Null when nothing was measured, rather than a confident zero or 100%.
  ErrorRate? get overallCer => _fold(scores.map((s) => s.cer));
  ErrorRate? get overallWer => _fold(scores.map((s) => s.wer));
  int get missingCount => scores.where((s) => s.missing).length;

  /// How many documents actually had an OCR hypothesis to score.
  int get measuredCount => scores.where((s) => s.cer != null).length;

  static ErrorRate? _fold(Iterable<ErrorRate?> rates) {
    final present = rates.whereType<ErrorRate>();
    if (present.isEmpty) return null;
    return present.fold<ErrorRate>(ErrorRate.zero, (sum, r) => sum + r);
  }

  List<double> get _sortedTimes =>
      scores.map((s) => s.milliseconds).toList()..sort();

  double get medianMilliseconds {
    final times = _sortedTimes;
    if (times.isEmpty) return 0;
    final middle = times.length ~/ 2;
    return times.length.isOdd
        ? times[middle]
        : (times[middle - 1] + times[middle]) / 2;
  }

  /// The slow tail is what a user actually notices, so it gets its own number.
  double get p90Milliseconds {
    final times = _sortedTimes;
    if (times.isEmpty) return 0;
    return times[((times.length - 1) * 0.9).round()];
  }

  Map<String, ErrorRate> get cerByCategory {
    final out = <String, ErrorRate>{};
    for (final score in scores) {
      final cer = score.cer;
      if (cer == null) continue;
      out[score.document.category] =
          (out[score.document.category] ?? ErrorRate.zero) + cer;
    }
    return out;
  }

  Map<String, ({double total, int count, bool anySkipped})> get stageTimings {
    final out = <String, ({double total, int count, bool anySkipped})>{};
    for (final document in run.documents) {
      for (final stage in document.stages) {
        final previous =
            out[stage.name] ?? (total: 0.0, count: 0, anySkipped: false);
        out[stage.name] = (
          total: previous.total + stage.milliseconds,
          count: previous.count + 1,
          anySkipped: previous.anySkipped || stage.skipped,
        );
      }
    }
    return out;
  }
}

/// Scores [run] against [dataset].
Scorecard score(Dataset dataset, RunResults run, {bool strict = false}) {
  final results = run.byId;
  final scores = <DocumentScore>[];
  for (final document in dataset.documents) {
    final reference = dataset.groundTruthOf(document);
    final result = results[document.id];
    final hypothesis = result?.text ?? '';
    // A result that exists but carries no text means no OCR ran, not that the
    // OCR read nothing — left unmeasured rather than scored 100%. A document
    // the run never produced at all is a different thing and stays a complete
    // failure, because that is a real miss and dropping it would flatter the
    // average.
    final unmeasured =
        result != null && hypothesis.isEmpty && reference.trim().isNotEmpty;
    scores.add(DocumentScore(
      document: document,
      cer: unmeasured
          ? null
          : characterErrorRate(reference, hypothesis, strict: strict),
      wer: unmeasured
          ? null
          : wordErrorRate(reference, hypothesis, strict: strict),
      milliseconds: result?.totalMilliseconds ?? 0,
      outputBytes: result?.outputBytes,
      missing: result == null,
    ));
  }
  return Scorecard(run: run, scores: scores, strict: strict);
}

String _pct(ErrorRate? rate) =>
    rate == null ? 'not measured' : '${(rate.rate * 100).toStringAsFixed(2)}%';
String _ms(double value) => '${value.toStringAsFixed(0)} ms';

/// Renders the Markdown report that goes into the repository.
String renderMarkdown(Scorecard card) {
  final run = card.run;
  final buffer = StringBuffer()
    ..writeln('# Evaluation run `${run.runId}`')
    ..writeln()
    ..writeln('| | |')
    ..writeln('|---|---|')
    ..writeln('| Device | ${run.device} |')
    ..writeln('| Platform | **${run.platform}** |')
    ..writeln('| Build | ${run.build ?? "—"} |')
    ..writeln('| Started | ${run.startedAt ?? "—"} |')
    ..writeln('| Pipeline | ${run.pipeline.join(" → ")} |')
    ..writeln('| Documents | ${card.scores.length} |')
    ..writeln(
        '| Normalisation | ${card.strict ? "strict" : "whitespace-collapsed"} |')
    ..writeln()
    ..writeln('> Every number below was measured on **${run.platform}**. '
        'Numbers are not transferable between platforms and this report never '
        'implies they are.')
    ..writeln();

  if (card.missingCount > 0) {
    buffer
      ..writeln('⚠️ ${card.missingCount} of ${card.scores.length} documents '
          'produced no output. They are counted as complete failures, not '
          'excluded from the averages.')
      ..writeln();
  }

  buffer
    ..writeln('## Overall')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---|')
    ..writeln('| Character error rate | **${_pct(card.overallCer)}** |')
    ..writeln('| Word error rate | ${_pct(card.overallWer)} |')
    ..writeln('| Median time per document | ${_ms(card.medianMilliseconds)} |')
    ..writeln('| 90th percentile | ${_ms(card.p90Milliseconds)} |')
    ..writeln();

  final stages = card.stageTimings;
  if (stages.isNotEmpty) {
    buffer
      ..writeln('## Per stage')
      ..writeln()
      ..writeln('| Stage | Mean time | Documents | Skipped anywhere |')
      ..writeln('|---|---|---|---|');
    for (final entry in stages.entries) {
      buffer.writeln('| ${entry.key} | '
          '${_ms(entry.value.total / entry.value.count)} | '
          '${entry.value.count} | ${entry.value.anySkipped ? "yes" : "no"} |');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Per category')
    ..writeln()
    ..writeln('| Category | CER |')
    ..writeln('|---|---|');
  final byCategory = card.cerByCategory.entries.toList()
    ..sort((a, b) => b.value.rate.compareTo(a.value.rate));
  for (final entry in byCategory) {
    buffer.writeln('| ${entry.key} | ${_pct(entry.value)} |');
  }

  buffer
    ..writeln()
    ..writeln('## Worst ten documents')
    ..writeln()
    ..writeln(
        'The point of publishing this table is that it is allowed to look bad.')
    ..writeln()
    ..writeln('| Document | Category | Conditions | CER | Time |')
    ..writeln('|---|---|---|---|---|');
  final worst = card.scores.where((s) => s.cer != null).toList()
    ..sort((a, b) => b.cer!.rate.compareTo(a.cer!.rate));
  for (final s in worst.take(10)) {
    buffer.writeln('| `${s.document.id}`${s.missing ? " (no output)" : ""} | '
        '${s.document.category} | ${s.document.conditions.join(", ")} | '
        '${_pct(s.cer)} | ${_ms(s.milliseconds)} |');
  }
  return buffer.toString();
}

/// Renders the same data as CSV, one row per document.
String renderCsv(Scorecard card) {
  final buffer = StringBuffer(
      'id,category,language,conditions,cer,wer,milliseconds,output_bytes,missing\n');
  for (final s in card.scores) {
    buffer.writeln(<String>[
      s.document.id,
      s.document.category,
      s.document.language,
      '"${s.document.conditions.join(" ")}"',
      s.cer?.rate.toStringAsFixed(6) ?? '',
      s.wer?.rate.toStringAsFixed(6) ?? '',
      s.milliseconds.toStringAsFixed(1),
      '${s.outputBytes ?? ""}',
      '${s.missing}',
    ].join(','));
  }
  return buffer.toString();
}

/// Renders the machine-readable form, for diffing two runs.
String renderJson(Scorecard card) =>
    const JsonEncoder.withIndent('  ').convert({
      'run': {
        'id': card.run.runId,
        'device': card.run.device,
        'platform': card.run.platform,
        'build': card.run.build,
        'pipeline': card.run.pipeline,
      },
      'strict': card.strict,
      'overall': {
        'cer': card.overallCer?.rate,
        'wer': card.overallWer?.rate,
        'measured': card.measuredCount,
        'medianMilliseconds': card.medianMilliseconds,
        'p90Milliseconds': card.p90Milliseconds,
        'documents': card.scores.length,
        'missing': card.missingCount,
      },
      'documents': [
        for (final s in card.scores)
          {
            'id': s.document.id,
            'category': s.document.category,
            'cer': s.cer?.rate,
            'wer': s.wer?.rate,
            'milliseconds': s.milliseconds,
            'missing': s.missing,
          }
      ],
    });
