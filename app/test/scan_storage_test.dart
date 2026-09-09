// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa/src/data/scan_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory cache;
  late ScanStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('byrsa_root');
    cache = Directory.systemTemp.createTempSync('byrsa_cache');
    storage = ScanStorage(root);
  });
  tearDown(() {
    root.deleteSync(recursive: true);
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  File cached(String name, [String content = 'scan']) =>
      File(p.join(cache.path, name))..writeAsStringSync(content);

  test('copies a captured page out of the cache directory', () async {
    // The bug this class exists for: byrsa_capture writes to the platform
    // cache, the operating system is entitled to empty it, and these are the
    // user's documents.
    final source = cached('byrsa-1.jpg');
    final kept = await storage.keep(source.path, documentId: 7);

    expect(p.isWithin(root.path, kept), isTrue);
    expect(File(kept).readAsStringSync(), 'scan');

    // Survives the cache being wiped, which is the whole point.
    cache.deleteSync(recursive: true);
    expect(File(kept).existsSync(), isTrue);
  });

  test('keeps pages of different documents apart', () async {
    final a = await storage.keep(cached('a.jpg', 'A').path, documentId: 1);
    final b = await storage.keep(cached('b.jpg', 'B').path, documentId: 2);
    expect(p.isWithin(storage.directoryFor(1).path, a), isTrue);
    expect(p.isWithin(storage.directoryFor(2).path, b), isTrue);
  });

  test('is idempotent, so keeping a kept file changes nothing', () async {
    final once = await storage.keep(cached('a.jpg').path, documentId: 3);
    final twice = await storage.keep(once, documentId: 3);
    expect(twice, once);
    expect(storage.directoryFor(3).listSync(), hasLength(1));
  });

  test('does not collide when two pages arrive with the same name', () async {
    final first =
        await storage.keep(cached('page.jpg', 'one').path, documentId: 4);
    final second =
        await storage.keep(cached('page.jpg', 'two').path, documentId: 4);
    expect(first, isNot(second));
    expect(File(first).readAsStringSync(), 'one');
    expect(File(second).readAsStringSync(), 'two');
  });

  test('discarding a document takes its images with it', () async {
    await storage.keep(cached('a.jpg').path, documentId: 5);
    await storage.keep(cached('b.jpg').path, documentId: 5);
    expect(storage.directoryFor(5).listSync(), hasLength(2));

    await storage.discard(5);
    expect(storage.directoryFor(5).existsSync(), isFalse);
  });

  test('discarding a document that has none is not an error', () async {
    await expectLater(storage.discard(99), completes);
  });
}
