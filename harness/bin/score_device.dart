// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// Scores text an Android device recognised against the corpus it came from.
//
//     dart run harness/bin/score_device.dart harness/out/device-ocr/pages.json
//
// The pages come back from `tool/ocr_on_device.sh` with no record of which
// corpus document each one was, because the application copies the picked file
// into its own cache and the original name is gone by then. So each page is
// matched to the ground truth it scores best against. That is safe here — the
// corpus documents share no wording — and it removes a bookkeeping step that
// could silently mislabel a result.
//
// Character error rate comes from `package:byrsa_harness`, the same
// implementation the rest of the project scores with. A second implementation
// would be a second answer.

import 'dart:convert';
import 'dart:io';

import 'package:byrsa_harness/byrsa_harness.dart';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('usage: score_device.dart <pages.json> [corpus dir]');
    exit(2);
  }
  final corpus = Directory(
      arguments.length > 1 ? arguments[1] : 'harness/dataset/synthetic');
  final dataset = Dataset.load(corpus);

  final pages = (jsonDecode(File(arguments[0]).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();

  final truths = <String, String>{
    for (final document in dataset.documents)
      document.id: dataset.groundTruthOf(document),
  };

  var total = ErrorRate.zero;
  var recognised = 0;
  final rows = <({String id, ErrorRate cer, ErrorRate wer, int chars})>[];

  for (final page in pages) {
    final text = (page['text'] as String?) ?? '';
    if (text.trim().isEmpty) continue;
    recognised++;

    // Best match wins. Ties cannot happen with documents this different.
    String? bestId;
    ErrorRate? best;
    for (final entry in truths.entries) {
      final rate = characterErrorRate(entry.value, text);
      if (best == null || rate.rate < best.rate) {
        best = rate;
        bestId = entry.key;
      }
    }
    if (bestId == null || best == null) continue;

    rows.add((
      id: bestId,
      cer: best,
      wer: wordErrorRate(truths[bestId]!, text),
      chars: text.length,
    ));
    total += best;
  }

  rows.sort((a, b) => a.cer.rate.compareTo(b.cer.rate));

  stdout
    ..writeln('| Document | Conditions | CER | WER | chars |')
    ..writeln('|---|---|---|---|---|');
  for (final row in rows) {
    final document =
        dataset.documents.firstWhere((candidate) => candidate.id == row.id);
    final conditions =
        document.conditions.where((c) => c != 'dense-text').join(', ');
    stdout.writeln('| `${row.id}` | ${conditions.isEmpty ? "—" : conditions} '
        '| ${_pct(row.cer)} | ${_pct(row.wer)} | ${row.chars} |');
  }

  stdout
    ..writeln()
    ..writeln('${pages.length} page(s) pulled, $recognised carried text.')
    ..writeln('Overall CER: ${_pct(total)} '
        '(${total.errors} errors over ${total.referenceLength} characters)');

  if (recognised < pages.length) {
    stdout.writeln('${pages.length - recognised} page(s) recognised nothing. '
        'That is a result, not a gap: it means the pipeline reached them and '
        'came back empty.');
  }
}

String _pct(ErrorRate rate) => '${(rate.rate * 100).toStringAsFixed(2)}%';
