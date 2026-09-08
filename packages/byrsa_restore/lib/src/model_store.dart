// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'model_catalog.dart';

/// Thrown when a model cannot be installed, always with a reason a user could
/// act on.
class ModelStoreException implements Exception {
  ModelStoreException(this.code, this.message);

  /// `unpinned`, `checksum-mismatch`, `http-<status>`, `network`.
  final String code;
  final String message;

  @override
  String toString() => 'ModelStoreException($code): $message';
}

/// Downloads, verifies and caches ONNX models on disk.
///
/// This is the machinery behind the only network request the application can
/// ever make. It is worth being precise about the guarantee, because the
/// README and the funding application both state it: no document leaves the
/// device, and the single outbound request is a model download the user starts.
///
/// Two rules are enforced here rather than documented:
///
/// 1. A model with no pinned SHA-256 is **not installed**. Trusting whatever a
///    URL returns is how a supply chain gets compromised, and "we will pin it
///    later" never happens.
/// 2. A file whose digest does not match is deleted, not kept and not used.
class ModelStore {
  ModelStore({
    required this.directory,
    required this.catalog,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Where installed models live. Cache, not application data: a model can
  /// always be fetched again, and the user is entitled to delete it.
  final Directory directory;

  final ModelCatalog catalog;
  final HttpClient Function() _httpClientFactory;

  File fileFor(String id) => File(p.join(directory.path, '$id.onnx'));

  bool isInstalled(String id) => fileFor(id).existsSync();

  /// Every model currently on disk.
  List<String> get installed => directory.existsSync()
      ? directory
          .listSync()
          .whereType<File>()
          .map((f) => p.basenameWithoutExtension(f.path))
          .toList()
      : <String>[];

  /// Bytes that would be downloaded to install [ids] — what the consent prompt
  /// should show before asking.
  int downloadSizeFor(Iterable<String> ids) => ids
      .where((id) => !isInstalled(id))
      .fold(0, (sum, id) => sum + catalog[id].sizeBytes);

  /// Downloads and verifies [id], unless it is already installed.
  ///
  /// [onProgress] receives bytes received and the expected total, for a
  /// progress bar the user can watch and cancel.
  Future<File> install(
    String id, {
    void Function(int received, int total)? onProgress,
  }) async {
    final model = catalog[id];
    final target = fileFor(id);
    if (target.existsSync()) return target;

    if (!model.isPinned) {
      throw ModelStoreException(
        'unpinned',
        'Model "$id" has no pinned SHA-256, so there is nothing to verify the '
            'download against. Run `dart run tool/pin_models.dart $id` and '
            'commit the result before shipping this model.',
      );
    }

    await directory.create(recursive: true);
    final temporary = File('${target.path}.part');
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(Uri.parse(model.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw ModelStoreException(
          'http-${response.statusCode}',
          'Downloading $id from ${model.url} returned ${response.statusCode}.',
        );
      }

      final total = response.contentLength > 0 ? response.contentLength : model.sizeBytes;
      final sink = temporary.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }

      // Hashed by streaming the file back off disk rather than holding a
      // 30 MB model in memory on a phone that is already tight.
      final actual = (await sha256.bind(temporary.openRead()).first).toString();
      if (actual != model.sha256) {
        await temporary.delete();
        throw ModelStoreException(
          'checksum-mismatch',
          'Model "$id" hashed to $actual, expected ${model.sha256}. '
              'The file was deleted and not used.',
        );
      }
      await temporary.rename(target.path);
      return target;
    } on SocketException catch (error) {
      if (temporary.existsSync()) await temporary.delete();
      throw ModelStoreException('network', 'Could not reach ${model.url}: ${error.message}');
    } finally {
      client.close();
    }
  }

  /// Removes an installed model. The user's disk is theirs.
  Future<void> remove(String id) async {
    final file = fileFor(id);
    if (file.existsSync()) await file.delete();
  }
}
