// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves one blob, so the download path is exercised for real rather than
/// mocked away. The interesting failures — a truncated file, a swapped blob —
/// only show up when bytes actually move.
Future<HttpServer> serve(List<int> body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = status;
    if (status == 200) request.response.add(body);
    await request.response.close();
  });
  return server;
}

String catalogJson(String url, String? digest, {int size = 4}) => jsonEncode({
      'models': [
        {
          'id': 'uvdoc',
          'url': url,
          'sizeBytes': size,
          'license': 'MIT',
          if (digest != null) 'sha256': digest,
        }
      ]
    });

void main() {
  late Directory cache;

  setUp(() => cache = Directory.systemTemp.createTempSync('byrsa_models'));
  tearDown(() => cache.deleteSync(recursive: true));

  test('installs a model whose digest matches', () async {
    final body = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));
    final server = await serve(body);
    addTearDown(server.close);

    final store = ModelStore(
      directory: cache,
      catalog: ModelCatalog.parse(catalogJson(
        'http://${server.address.host}:${server.port}/uvdoc.onnx',
        sha256.convert(body).toString(),
        size: body.length,
      )),
    );

    final file = await store.install('uvdoc');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), body);
    expect(store.isInstalled('uvdoc'), isTrue);
  });

  test('deletes and refuses a model whose digest does not match', () async {
    // A blob that is not what the manifest says it is must never reach an
    // inference session, and must not be left on disk to be retried into.
    final server = await serve(Uint8List.fromList(<int>[9, 9, 9, 9]));
    addTearDown(server.close);

    final store = ModelStore(
      directory: cache,
      catalog: ModelCatalog.parse(catalogJson(
        'http://${server.address.host}:${server.port}/uvdoc.onnx',
        'a' * 64,
      )),
    );

    await expectLater(
      store.install('uvdoc'),
      throwsA(isA<ModelStoreException>()
          .having((e) => e.code, 'code', 'checksum-mismatch')),
    );
    expect(store.isInstalled('uvdoc'), isFalse);
    expect(cache.listSync(), isEmpty,
        reason: 'no half-downloaded file left behind');
  });

  test('refuses to install a model nobody has pinned', () async {
    // "We will pin it later" is how a supply chain gets compromised.
    final server = await serve(<int>[1, 2, 3, 4]);
    addTearDown(server.close);

    final store = ModelStore(
      directory: cache,
      catalog: ModelCatalog.parse(catalogJson(
        'http://${server.address.host}:${server.port}/uvdoc.onnx',
        null,
      )),
    );

    await expectLater(
      store.install('uvdoc'),
      throwsA(
          isA<ModelStoreException>().having((e) => e.code, 'code', 'unpinned')),
    );
  });

  test('reports an HTTP failure with its status', () async {
    final server = await serve(const <int>[], status: 404);
    addTearDown(server.close);

    final store = ModelStore(
      directory: cache,
      catalog: ModelCatalog.parse(catalogJson(
        'http://${server.address.host}:${server.port}/uvdoc.onnx',
        'b' * 64,
      )),
    );

    await expectLater(
      store.install('uvdoc'),
      throwsA(
          isA<ModelStoreException>().having((e) => e.code, 'code', 'http-404')),
    );
  });

  test('tells the user what a download will cost before it starts', () {
    final store = ModelStore(
      directory: cache,
      catalog: ModelCatalog.parse(
        catalogJson('http://example.invalid/uvdoc.onnx', 'c' * 64,
            size: 31000000),
      ),
    );
    expect(store.downloadSizeFor(<String>['uvdoc']), 31000000);
  });

  group('catalogue', () {
    test('flags models that may not be shipped yet', () {
      final catalog = ModelCatalog.parse(jsonEncode({
        'models': [
          {
            'id': 'pinned',
            'url': 'https://x/1',
            'license': 'MIT',
            'sha256': 'd' * 64
          },
          {'id': 'unpinned', 'url': 'https://x/2', 'license': 'MIT'},
          {'id': 'unaudited', 'url': 'https://x/3', 'sha256': 'e' * 64},
        ]
      }));
      expect(
          catalog.blockers.map((m) => m.id), <String>['unpinned', 'unaudited']);
    });

    test('names the models it knows when asked for one it does not', () {
      final catalog = ModelCatalog.parse(catalogJson('https://x/1', 'f' * 64));
      expect(() => catalog['nope'], throwsArgumentError);
    });
  });
}
