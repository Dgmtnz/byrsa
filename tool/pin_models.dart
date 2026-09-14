// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

// Pins the SHA-256 and size of every model in models.json, by downloading it.
//
//   dart run tool/pin_models.dart            # everything unpinned
//   dart run tool/pin_models.dart uvdoc      # one model
//   dart run tool/pin_models.dart --verify   # re-check what is already pinned
//
// Why this exists rather than a hash pasted from a model card: a hash nobody
// computed is a hash nobody can defend, and `ModelStore` refuses to install an
// unpinned model. Re-running with --verify is also how the project finds out
// that a "stable" URL started serving something else.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final verify = arguments.contains('--verify');
  final wanted = arguments.where((a) => !a.startsWith('--')).toSet();

  final file = File('models.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final models = (json['models']! as List).cast<Map<String, Object?>>();

  var changed = false;
  var failed = false;

  for (final model in models) {
    final id = model['id']! as String;
    if (wanted.isNotEmpty && !wanted.contains(id)) continue;

    for (final file in _filesOf(model)) {
      final label =
          file['fileName'] == null ? id : '$id/${file['fileName']}';
      final pinned = file['sha256'] as String?;
      if (pinned != null && !verify) {
        stdout.writeln(
            '$label: already pinned, skipping (use --verify to re-check)');
        continue;
      }

      stdout.write('$label: downloading… ');
      final (:digest, :size) = await _hash(Uri.parse(file['url']! as String));
      if (pinned == null) {
        file['sha256'] = digest;
        file['sizeBytes'] = size;
        changed = true;
        stdout.writeln('pinned $digest ($size bytes)');
      } else if (pinned == digest) {
        stdout.writeln('unchanged');
      } else {
        failed = true;
        stdout.writeln('CHANGED\n'
            '  was $pinned\n'
            '  now $digest\n'
            '  The file behind this URL is not the file we pinned. Do not '
            'update the manifest until you know why.');
      }
    }
  }

  if (changed) {
    file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n');
    stdout.writeln('Wrote models.json. Commit it.');
  }
  if (failed) exit(1);
}

/// Every file of a model, whichever of the two shapes the manifest used.
///
/// A model is not always one file: UVDoc's grid export arrived with a `.data`
/// sidecar, and with it the `files` array. `ModelCatalog` was taught that shape
/// at the time and this tool was not, so it read a null `url` off the first
/// multi-file model and crashed — taking `--verify` with it, which is the
/// command `UNVERIFIED.md` names as the way to re-check every pin. Normalising
/// here the same way `ModelDescriptor.fromJson` does is what stops the two
/// readers of this manifest drifting apart again.
List<Map<String, Object?>> _filesOf(Map<String, Object?> model) =>
    (model['files'] as List?)?.cast<Map<String, Object?>>() ??
    <Map<String, Object?>>[model];

/// Streams a URL through SHA-256 without holding it in memory.
Future<({String digest, int size})> _hash(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      throw StateError('$url returned ${response.statusCode}');
    }
    final temporary = File(
      '${Directory.systemTemp.path}/byrsa-pin-${url.pathSegments.last}',
    );
    final sink = temporary.openWrite();
    var size = 0;
    await for (final chunk in response) {
      sink.add(chunk);
      size += chunk.length;
    }
    await sink.close();
    final digest = (await sha256.bind(temporary.openRead()).first).toString();
    await temporary.delete();
    return (digest: digest, size: size);
  } finally {
    client.close();
  }
}
