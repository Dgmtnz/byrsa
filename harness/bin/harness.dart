// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// The evaluation harness. One command, reproducible by anyone who clones the
// repository:
//
//   dart run harness/bin/harness.dart score --results out/pixel6a-2026-09-20.json
//
// Scoring is separate from running the pipeline on purpose: a run happens on a
// device and writes JSON, and the maths happens here. See DECISIONS.md D-019.

import 'dart:convert';
import 'dart:io';

import 'package:byrsa_restore/byrsa_restore.dart';

import 'package:byrsa_harness/byrsa_harness.dart';

const String _usage = '''
byrsa evaluation harness

Usage:
  dart run harness/bin/harness.dart run [options]
  dart run harness/bin/harness.dart score --results <run.json> [options]
  dart run harness/bin/harness.dart synth [options]
  dart run harness/bin/harness.dart validate

Commands:
  run        Execute the restoration pipeline over the dataset and write a run
             file. Runs the same code the application ships. No OCR engine
             here, so character error rate is left to a run from a device.
  score      Score a run against the dataset and write a report.
  synth      Generate a synthetic corpus with clean originals. NOT the
             evaluation set — it exists so the pipeline can be exercised and
             regressions caught before the fifty photographs exist.
  validate   Check the dataset manifest: files present, ground truth readable,
             licences declared, publishable flags consistent.

Options for run:
  --dataset <dir>    Dataset directory.       (default: harness/dataset)
  --out <path>       Run file to write.       (default: harness/out/run.json)
  --images <dir>     Where to keep restored images. Omit to skip writing them.
  --filter <name>    colour | grayscale | blackAndWhite   (default: colour)
  --analysis <px>    Analysis width for the restoration.  (default: 512)
  --device <text>    What produced this run. Be specific.

Options for synth:
  --out <dir>        Where to generate.       (default: harness/synthetic)
  --count <n>        How many documents.      (default: 10)

Options for score:
  --results <path>   Run output produced on a device.        (required)
  --dataset <dir>    Dataset directory.       (default: harness/dataset)
  --out <dir>        Where to write the report. (default: harness/out)
  --strict           Do not collapse whitespace before comparing.
''';

void main(List<String> arguments) {
  final command = arguments.isEmpty ? '' : arguments.first;
  final options = _parseOptions(arguments.skip(1).toList());

  final datasetDir = Directory(options['dataset'] ?? 'harness/dataset');

  switch (command) {
    case 'score':
      final resultsPath =
          options['results'] ?? _fail('score needs --results <run.json>');
      final dataset = Dataset.load(datasetDir);
      final run = RunResults.load(File(resultsPath));
      final card = score(dataset, run, strict: options.containsKey('strict'));

      final outDir = Directory(options['out'] ?? 'harness/out')
        ..createSync(recursive: true);
      final base = '${outDir.path}/${run.runId}';
      File('$base.md').writeAsStringSync(renderMarkdown(card));
      File('$base.csv').writeAsStringSync(renderCsv(card));
      File('$base.json').writeAsStringSync(renderJson(card));

      stdout
        ..writeln(renderMarkdown(card))
        ..writeln('Wrote $base.{md,csv,json}');

    case 'run':
      final dataset = Dataset.load(
        Directory(options['dataset'] ?? 'harness/dataset'),
      );
      if (dataset.documents.isEmpty) {
        _fail('The dataset at ${dataset.directory.path} has no documents. '
            'Generate a synthetic one with `synth`, or point --dataset at the '
            'real set once the photographs exist.');
      }
      final filterName = options['filter'] ?? 'colour';
      final filter = PageFilter.values.firstWhere(
        (value) => value.name == filterName,
        orElse: () => _fail('Unknown --filter "$filterName". Use '
            '${PageFilter.values.map((v) => v.name).join(", ")}.'),
      );
      final runner = PipelineRunner(
        filter: filter,
        analysisWidth: int.tryParse(options['analysis'] ?? '') ?? 512,
        writeOutput: options['images'] != null,
      );
      final results = runner.run(
        dataset,
        runId: options['run-id'] ??
            'local-${filter.name}-${dataset.documents.length}',
        device: options['device'] ?? 'unspecified host, `harness run`',
        outputDirectory:
            options['images'] == null ? null : Directory(options['images']!),
        onDocument: (done, total, id) => stdout.writeln('  [$done/$total] $id'),
      );

      final outPath = options['out'] ?? 'harness/out/run.json';
      File(outPath).parent.createSync(recursive: true);
      File(outPath).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(results.toJson())}\n',
      );
      stdout
        ..writeln()
        ..writeln('Wrote $outPath')
        ..writeln('Score it: dart run harness/bin/harness.dart score '
            '--results $outPath --dataset ${dataset.directory.path}');

    case 'synth':
      final target = Directory(options['out'] ?? 'harness/synthetic');
      final count = int.tryParse(options['count'] ?? '') ?? 10;
      const SyntheticCorpus().write(target, count: count);
      stdout
        ..writeln('Generated $count synthetic documents in ${target.path}')
        ..writeln('These are NOT the evaluation set. They have a clean '
            'original and no text, so they measure restoration and not OCR.')
        ..writeln()
        ..writeln('  dart run harness/bin/harness.dart run '
            '--dataset ${target.path}');

    case 'validate':
      final problems = _validate(datasetDir);
      if (problems.isEmpty) {
        final dataset = Dataset.load(datasetDir);
        stdout.writeln('Dataset OK: ${dataset.documents.length} documents, '
            'categories ${dataset.categories.join(", ")}.');
        if (dataset.documents.length != 50) {
          stdout.writeln('Note: the plan fixes the set at 50 documents; '
              'this manifest has ${dataset.documents.length}.');
        }
      } else {
        for (final problem in problems) {
          stderr.writeln('- $problem');
        }
        exit(1);
      }

    default:
      stdout.writeln(_usage);
      exit(command.isEmpty ? 0 : 64);
  }
}

Never _fail(String message) {
  stderr
    ..writeln('error: $message')
    ..writeln()
    ..writeln(_usage);
  exit(64);
}

Map<String, String?> _parseOptions(List<String> arguments) {
  final options = <String, String?>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (!argument.startsWith('--')) continue;
    final name = argument.substring(2);
    final hasValue =
        i + 1 < arguments.length && !arguments[i + 1].startsWith('--');
    options[name] = hasValue ? arguments[++i] : null;
  }
  return options;
}

List<String> _validate(Directory directory) {
  final problems = <String>[];
  final Dataset dataset;
  try {
    dataset = Dataset.load(directory);
  } on Object catch (error) {
    return <String>['$error'];
  }

  final seen = <String>{};
  for (final document in dataset.documents) {
    if (!seen.add(document.id)) {
      problems.add('duplicate id "${document.id}"');
    }
    for (final path in <String>[document.file, document.groundTruth]) {
      if (!File('${directory.path}/$path').existsSync()) {
        problems.add('${document.id}: missing $path');
      }
    }
    if (document.publish && document.license == null) {
      problems
          .add('${document.id}: marked publishable but declares no licence');
    }
    if (document.publish && document.file.startsWith('private/')) {
      problems.add('${document.id}: marked publishable but lives in private/ — '
          'personal data must not be published (plan §5)');
    }
  }
  return problems;
}
