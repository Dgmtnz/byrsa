// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa/src/data/library_database.dart';
import 'package:byrsa/src/data/scan_storage.dart';
import 'package:byrsa/src/domain/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

LibraryDatabase open() => LibraryDatabase(sqlite3.openInMemory());

int pageWithText(LibraryDatabase db, int documentId, String text) =>
    db.addPage(documentId, originalPath: '/scans/x.jpg', text: text);

void main() {
  late LibraryDatabase db;

  setUp(() => db = open());
  tearDown(() => db.dispose());

  group('schema', () {
    test('creates itself and records its version', () {
      expect(LibraryDatabase.schemaVersion, 3);
      expect(db.documents(), isEmpty);
    });

    test('deleting a document takes its pages with it', () {
      final id = db.createDocument('Factura');
      pageWithText(db, id, 'hola');
      db.deleteDocument(id);
      expect(db.pagesOf(id), isEmpty);
      expect(db.search('hola'), isEmpty,
          reason: 'the index must not outlive the page');
    });
  });

  group('pages', () {
    test('are numbered in the order they are added', () {
      final id = db.createDocument('Contrato');
      db.addPage(id, originalPath: 'a.jpg');
      db.addPage(id, originalPath: 'b.jpg');
      db.addPage(id, originalPath: 'c.jpg');
      expect(db.pagesOf(id).map((p) => p.position), <int>[0, 1, 2]);
    });

    test('reorder in one transaction, never leaving two pages at one position',
        () {
      final id = db.createDocument('Contrato');
      final a = db.addPage(id, originalPath: 'a.jpg');
      final b = db.addPage(id, originalPath: 'b.jpg');
      final c = db.addPage(id, originalPath: 'c.jpg');

      db.reorderPages(id, <int>[c, a, b]);
      expect(db.pagesOf(id).map((p) => p.originalPath),
          <String>['c.jpg', 'a.jpg', 'b.jpg']);
      expect(db.pagesOf(id).map((p) => p.position), <int>[0, 1, 2]);
    });

    test('report whether the document is searchable', () {
      final id = db.createDocument('Recibo');
      db.addPage(id, originalPath: 'a.jpg');
      expect(db.document(id)!.isSearchable, isFalse);

      db.setPageText(db.pagesOf(id).first.id, 'total 12,40');
      expect(db.document(id)!.isSearchable, isTrue);
    });
  });

  group('full-text search', () {
    late int documentId;

    setUp(() {
      documentId = db.createDocument('Factura de la luz');
      pageWithText(
          db, documentId, 'Importe total de la facturación: 84,20 EUR');
      pageWithText(db, documentId, 'Consumo en el periodo de enero');
    });

    test('finds a word inside a page', () {
      final hits = db.search('consumo');
      expect(hits, hasLength(1));
      expect(hits.single.documentId, documentId);
      expect(hits.single.pagePosition, 1);
    });

    test('ignores accents, because nobody types them into a search box', () {
      expect(db.search('facturacion'), hasLength(1));
      expect(db.search('FACTURACIÓN'), hasLength(1));
    });

    test('matches a prefix, so search-as-you-type works', () {
      expect(db.search('fact'), isNotEmpty);
    });

    test('requires every term, not any of them', () {
      expect(db.search('consumo enero'), hasLength(1));
      expect(db.search('consumo bicicleta'), isEmpty);
    });

    test('marks the match in the snippet it returns', () {
      expect(db.search('consumo').single.snippet, contains('[Consumo]'));
    });

    test('survives characters that would be FTS5 syntax errors', () {
      // A user typing a quote or a star must get no results, not a crash.
      for (final query in <String>['"', '*', 'total "', 'a AND', '()']) {
        expect(() => db.search(query), returnsNormally, reason: query);
      }
    });

    test('reindexes when a page is edited, and drops it when deleted', () {
      final page = db.pagesOf(documentId).first;
      db.setPageText(page.id, 'texto completamente distinto');
      expect(db.search('importe'), isEmpty);
      expect(db.search('distinto'), hasLength(1));

      db.deletePage(page.id);
      expect(db.search('distinto'), isEmpty);
    });
  });

  group('restoration state', () {
    test('a freshly captured page is rectified but not restored', () {
      // The distinction the background enhancement depends on. Without it the
      // application either redoes finished work or never finishes it.
      final id = db.createDocument('Escaneo');
      final pageId = db.addPage(
        id,
        originalPath: 'raw.jpg',
        processedPath: 'raw.jpg.page.jpg',
      );
      final page = db.pagesOf(id).single;
      expect(page.processedPath, 'raw.jpg.page.jpg');
      expect(page.restored, isFalse);

      db.setPageRestored(pageId);
      expect(db.pagesOf(id).single.restored, isTrue);
      expect(db.pagesOf(id).single.displayPath, 'raw.jpg.enhanced.jpg');
      expect(db.pagesOf(id).single.processedPath, 'raw.jpg.page.jpg',
          reason: 'the rectified page must survive its own restoration');
    });

    test('the corners found at capture reach the row', () {
      // They used to be accepted as an argument and dropped from the INSERT,
      // so "adjust corners" opened on the full frame every time and the
      // detector's work was thrown away at the moment it was done.
      final id = db.createDocument('Escaneo');
      db.addPage(
        id,
        originalPath: 'raw.jpg',
        quad: const <double>[0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9],
        words: const <PageWord>[
          PageWord(text: 'Total', left: 1, top: 2, right: 3, bottom: 4),
        ],
      );
      final page = db.pagesOf(id).single;
      expect(page.quad, <double>[0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);
      expect(page.words.single.text, 'Total');
    });

    test('changing the filter restores the rectified page, not the last result',
        () {
      // The filter compounded on itself: `processed_path` was overwritten with
      // the restoration output, so the next pass read its own previous result
      // and, since the output name was derived from the original either way,
      // wrote it back to the same file (D-051).
      final id = db.createDocument('Escaneo');
      final pageId = db.addPage(
        id,
        originalPath: '/scans/raw.jpg',
        processedPath: '/scans/raw.jpg.page.jpg',
      );
      db.setPageRestored(pageId);

      db.setPagesNeedRestore(id);
      final again = db.pagesOf(id).single;
      expect(again.restored, isFalse);

      // What the restoration loop reads, and where it writes.
      final input = again.restoreInput((_) => true);
      expect(input, '/scans/raw.jpg.page.jpg',
          reason: 'the previous restoration must never become the input');
      expect(again.restoreInput((_) => false), '/scans/raw.jpg',
          reason: 'a warp the OS has purged falls back to the original');
    });

    test('a filter change re-queues its own document and no other', () {
      // Two documents so page and document ids differ: a WHERE on the wrong
      // column would still pass with one of each.
      final decoy = db.createDocument('Otro');
      final decoyPages = <int>[
        db.addPage(decoy, originalPath: 'a.jpg'),
        db.addPage(decoy, originalPath: 'b.jpg'),
      ];
      final target = db.createDocument('Escaneo');
      final targetPages = <int>[
        db.addPage(target, originalPath: 'c.jpg'),
        db.addPage(target, originalPath: 'd.jpg'),
      ];
      [...decoyPages, ...targetPages].forEach(db.setPageRestored);

      db.setPagesNeedRestore(target);
      expect(db.pagesOf(target).map((p) => p.restored), <bool>[false, false]);
      expect(db.pagesOf(decoy).map((p) => p.restored), <bool>[true, true]);
    });

    test('a database written before the split keeps the best picture it has',
        () {
      // v1 stored the restoration output in `processed_path`, which is the
      // column the next restoration reads. The tables are identical in v1 and
      // v2 — only the meaning of that column changed — so the fixture is the
      // real schema with `user_version` wound back, v1-shaped rows, and the
      // files each of them still has on disk.
      final dir = Directory.systemTemp.createTempSync('byrsa_migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      String file(String name) {
        final path = '${dir.path}/$name';
        File(path).writeAsStringSync('');
        return path;
      }

      // A capture whose warp survived.
      final captured = file('captured.jpg');
      file('captured.jpg.page.jpg');
      file('captured.jpg.restored.jpg');
      // A gallery import, which never had a warp, caught by the upgrade in
      // the middle of a filter change (restored = 0).
      final imported = file('imported.jpg');
      file('imported.jpg.restored.jpg');
      // A capture whose original and warp the OS purged.
      final purged = '${dir.path}/purged.jpg';
      final survivor = file('purged.jpg.restored.jpg');
      // A capture v1 never got round to restoring: not the migration's.
      final pending = file('pending.jpg');

      final raw = sqlite3.openInMemory();
      LibraryDatabase(raw);
      raw.execute('PRAGMA user_version = 1');
      raw.execute(
        "INSERT INTO documents(title, created_at, updated_at) "
        "VALUES ('Escaneo', 0, 0)",
      );
      final insert = raw.prepare(
        'INSERT INTO pages(document_id, position, original_path, '
        'processed_path, restored) VALUES (1, ?, ?, ?, ?)',
      );
      insert.execute(<Object?>[0, captured, '$captured.restored.jpg', 1]);
      insert.execute(<Object?>[1, imported, '$imported.restored.jpg', 0]);
      insert.execute(<Object?>[2, purged, survivor, 1]);
      insert.execute(<Object?>[3, pending, '$pending.page.jpg', 0]);
      insert.dispose();

      final migrated = LibraryDatabase(raw);
      final pages = migrated.pagesOf(1);
      expect(pages.map((p) => p.restored), everyElement(isFalse),
          reason: 'every page is queued to be enhanced again');
      expect(pages[0].processedPath, '$captured.page.jpg',
          reason: 'Android capture writes the warp under that name');
      expect(pages[1].processedPath, isNull,
          reason: 'no warp on disk: restoration starts from the original');
      expect(pages[1].displayPath, imported);
      expect(pages[2].processedPath, survivor,
          reason: 'the only picture left must stay referenced');
      expect(pages[2].displayPath, survivor);
      expect(pages[3].processedPath, '$pending.page.jpg',
          reason: 'a row that never held a restoration is left alone');
      migrated.dispose();
    });

    test('re-warping a page marks it as needing restoration again', () {
      // Corners corrected after the fact produce a new rectified image, and
      // the old restored one no longer describes it.
      final id = db.createDocument('Escaneo');
      final pageId = db.addPage(id, originalPath: 'raw.jpg');
      db.setPageRestored(pageId);
      expect(db.pagesOf(id).single.restored, isTrue);

      db.setPageProcessed(pageId, 'raw.jpg.page.jpg');
      expect(db.pagesOf(id).single.restored, isFalse);
    });
  });

  group('files (D-056)', () {
    late Directory root;
    late Directory cache;

    setUp(() {
      root = Directory.systemTemp.createTempSync('byrsa_root');
      cache = Directory.systemTemp.createTempSync('byrsa_cache');
    });
    tearDown(() {
      root.deleteSync(recursive: true);
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    });

    String cached(String name, String content) =>
        (File(p.join(cache.path, name))..writeAsStringSync(content)).path;

    List<Object?> storedPaths(Database raw) => raw
        .select('SELECT original_path, processed_path FROM pages ORDER BY id')
        .expand((row) => <Object?>[row['original_path'], row['processed_path']])
        .toList();

    test('capture and import keep their files out of the cache, relatively',
        () async {
      // Both used to store the path the plugin or image_picker returned, the
      // only copy in a directory the OS may empty.
      final raw = sqlite3.openInMemory();
      final library = LibraryDatabase(raw, storage: ScanStorage(root));
      addTearDown(library.dispose);
      final id = library.createDocument('Escaneo');

      // The iOS source names its warp from a fresh timestamp, not the frame.
      await library.keepPage(
        id,
        originalPath: cached('byrsa-1.jpg', 'frame'),
        rectifiedPath: cached('byrsa-2.page.jpg', 'warp'),
        quad: const <double>[0, 0, 1, 0, 1, 1, 0, 1],
      );
      await library.keepPage(id, originalPath: cached('IMG_0001.jpg', 'photo'));
      cache.deleteSync(recursive: true);

      final [captured, imported] = library.pagesOf(id);
      final folder = ScanStorage(root).directoryFor(id).path;
      expect(p.isWithin(folder, captured.originalPath), isTrue);
      expect(File(captured.originalPath).readAsStringSync(), 'frame');
      expect(captured.processedPath, '${captured.originalPath}.page.jpg',
          reason: 'the name the re-warp writes and the D-051 migration reads');
      expect(File(captured.processedPath!).readAsStringSync(), 'warp');
      expect(p.isWithin(folder, captured.restoredPath), isTrue);
      expect(File(imported.originalPath).readAsStringSync(), 'photo');
      expect(imported.processedPath, isNull);

      // The re-warp after "adjust corners" writes beside the kept frame.
      library.setPageProcessed(
          captured.id, '${captured.originalPath}.page.jpg');
      expect(storedPaths(raw).whereType<String>(),
          everyElement(isNot(startsWith('/'))),
          reason: 'stored relative to the root, as D-015 promised');
    });

    test('a page whose files cannot be copied is not saved', () async {
      final library =
          LibraryDatabase(sqlite3.openInMemory(), storage: ScanStorage(root));
      addTearDown(library.dispose);
      final id = library.createDocument('Escaneo');
      await expectLater(
        library.keepPage(id, originalPath: p.join(cache.path, 'purged.jpg')),
        throwsA(isA<FileSystemException>()),
      );
      expect(library.pagesOf(id), isEmpty,
          reason: 'a row pointing at nothing is the bug, not the error');
    });

    test('a warp the OS already purged costs the crop, not the page', () async {
      final library =
          LibraryDatabase(sqlite3.openInMemory(), storage: ScanStorage(root));
      addTearDown(library.dispose);
      final id = library.createDocument('Escaneo');
      await library.keepPage(
        id,
        originalPath: cached('byrsa-1.jpg', 'frame'),
        rectifiedPath: p.join(cache.path, 'byrsa-1.jpg.page.jpg'),
        quad: const <double>[0, 0, 1, 0, 1, 1, 0, 1],
      );

      final page = library.pagesOf(id).single;
      expect(File(page.originalPath).readAsStringSync(), 'frame');
      expect(page.processedPath, isNull,
          reason: 'restoration falls back to the frame');
      expect(page.quad, isNotNull,
          reason: 'and "adjust corners" can warp it again');
      expect(ScanStorage(root).directoryFor(id).listSync(), hasLength(1),
          reason: 'no copy is left behind without a row');
    });

    test('a library whose root moved still finds every page', () async {
      // What D-015 exists for: the iOS container path changes across updates.
      final before = Directory(p.join(root.path, 'before'))..createSync();
      final library = LibraryDatabase(
        sqlite3.open(p.join(before.path, 'library.db')),
        storage: ScanStorage(before),
      );
      final id = library.createDocument('Escaneo');
      await library.keepPage(
        id,
        originalPath: cached('byrsa-1.jpg', 'frame'),
        rectifiedPath: cached('byrsa-1.jpg.page.jpg', 'warp'),
      );
      library.dispose();

      final after = before.renameSync(p.join(root.path, 'after'));
      final reopened = LibraryDatabase(
        sqlite3.open(p.join(after.path, 'library.db')),
        storage: ScanStorage(after),
      );
      addTearDown(reopened.dispose);
      final page = reopened.pagesOf(id).single;
      expect(p.isWithin(after.path, page.originalPath), isTrue);
      expect(File(page.originalPath).readAsStringSync(), 'frame');
      expect(File(page.processedPath!).readAsStringSync(), 'warp');
    });

    group('schema 2 -> 3', () {
      // The tables are identical in schema 2 and 3; only where the files are
      // and how their paths are written changed. So the fixture is the real
      // schema with `user_version` wound back and schema 2 rows: absolute
      // paths, into the cache.
      late Database raw;
      late String frame;
      late String inside;

      setUp(() {
        raw = sqlite3.openInMemory();
        LibraryDatabase(raw);
        raw.execute('PRAGMA user_version = 2');
        raw.execute("INSERT INTO documents(title, created_at, updated_at) "
            "VALUES ('Escaneo', 0, 0)");

        // 1. A restored capture: frame, warp and enhanced output in the cache.
        frame = cached('byrsa-1.jpg', 'frame');
        cached('byrsa-1.jpg.page.jpg', 'warp');
        cached('byrsa-1.jpg.enhanced.jpg', 'enhanced');
        // 2. A capture the OS purged before the upgrade.
        final gone = p.join(cache.path, 'gone.jpg');
        // 3. A page already inside the root.
        inside = p.join(root.path, 'scans', '1', '123.jpg');
        Directory(p.dirname(inside)).createSync(recursive: true);
        File(inside).writeAsStringSync('inside');
        // 4. A schema 1 page whose restoration is the only picture left
        //    (D-051, case 3).
        final purged = p.join(cache.path, 'purged.jpg');
        final survivor = cached('purged.jpg.restored.jpg', 'survivor');
        // 5. An import the OS purged whose restoration survived: the only
        //    picture of the page, and named after the frame.
        final picked = p.join(cache.path, 'image_picker1.jpg');
        cached('image_picker1.jpg.enhanced.jpg', 'enhanced import');

        final insert = raw.prepare(
          'INSERT INTO pages(document_id, position, original_path, '
          'processed_path, restored) VALUES (1, ?, ?, ?, ?)',
        );
        insert.execute(<Object?>[0, frame, '$frame.page.jpg', 1]);
        insert.execute(<Object?>[1, gone, '$gone.page.jpg', 0]);
        insert.execute(<Object?>[2, inside, null, 0]);
        insert.execute(<Object?>[3, purged, survivor, 0]);
        insert.execute(<Object?>[4, picked, null, 1]);
        insert.dispose();
      });
      tearDown(() => raw.dispose());

      List<ScanPage> migrate() =>
          LibraryDatabase(raw, storage: ScanStorage(root)).pagesOf(1);
      int version() =>
          raw.select('PRAGMA user_version').first['user_version'] as int;

      test('copies what the cache still has and stores it relatively', () {
        final pages = migrate();
        final folder = ScanStorage(root).directoryFor(1).path;

        final restored = pages[0];
        expect(p.isWithin(folder, restored.originalPath), isTrue);
        expect(File(restored.originalPath).readAsStringSync(), 'frame');
        expect(restored.processedPath, '${restored.originalPath}.page.jpg');
        expect(File(restored.processedPath!).readAsStringSync(), 'warp');
        expect(File(restored.restoredPath).readAsStringSync(), 'enhanced',
            reason: 'a restored page keeps its restoration');
        expect(restored.restored, isTrue,
            reason: 'and is not queued to be restored again');

        expect(pages[1].originalPath, p.join(folder, '2-gone.jpg'),
            reason: 'a file that is gone moves too: it named nothing and '
                'still does');
        expect(pages[1].processedPath, '${pages[1].originalPath}.page.jpg');
        expect(pages[2].originalPath, inside);
        expect(pages[3].originalPath, p.join(folder, '4-purged.jpg'));
        expect(p.isWithin(folder, pages[3].processedPath!), isTrue);
        expect(File(pages[3].processedPath!).readAsStringSync(), 'survivor',
            reason: 'the only picture left of the page comes out too');

        final picked = pages[4];
        expect(picked.originalPath, p.join(folder, '5-image_picker1.jpg'));
        expect(File(picked.restoredPath).readAsStringSync(), 'enhanced import',
            reason: 'a restoration outlives its purged frame, and every later '
                'one is written into storage, not the cache');
        expect(picked.restored, isTrue);

        final stored = storedPaths(raw);
        expect(stored[0], p.relative(restored.originalPath, from: root.path));
        expect(stored[1], p.relative(restored.processedPath!, from: root.path));
        expect(stored[2], p.join('scans', '1', '2-gone.jpg'));
        expect(stored[4], p.join('scans', '1', '123.jpg'));
        expect(File(frame).existsSync(), isTrue,
            reason: 'nothing is deleted; the cache is the OS\'s to empty');
        expect(version(), 3);
      });

      test('running it again, even after an interrupted run, changes nothing',
          () {
        final first = migrate();
        final files = ScanStorage(root).directoryFor(1).listSync().length;

        raw.execute('PRAGMA user_version = 2');
        expect(migrate().map((page) => page.originalPath),
            first.map((page) => page.originalPath));

        // Interrupted after the copies and before the row was written.
        raw.execute('PRAGMA user_version = 2');
        raw.execute(
            'UPDATE pages SET original_path = ?, processed_path = ? '
            'WHERE id = 1',
            <Object?>[frame, '$frame.page.jpg']);
        final copies = <File>[
          for (final path in <String>[
            first[0].originalPath,
            first[0].processedPath!,
            first[0].restoredPath,
          ])
            File(path)..setLastModifiedSync(DateTime(2000)),
        ];
        final again = migrate();
        expect(again[0].originalPath, first[0].originalPath,
            reason: 'its own copy is recognised and used');
        expect(again[0].processedPath, first[0].processedPath);
        expect(ScanStorage(root).directoryFor(1).listSync(), hasLength(files),
            reason: 'and nothing is copied twice');
        expect(copies.map((copy) => copy.lastModifiedSync()),
            everyElement(DateTime(2000)),
            reason: 'nor written again');

        // Interrupted the same way, and the OS emptied the cache before the
        // next launch: the copies are all there is.
        raw.execute('PRAGMA user_version = 2');
        raw.execute(
            'UPDATE pages SET original_path = ?, processed_path = ? '
            'WHERE id = 1',
            <Object?>[frame, '$frame.page.jpg']);
        cache.deleteSync(recursive: true);
        final purged = migrate();
        expect(purged[0].originalPath, first[0].originalPath);
        expect(File(purged[0].originalPath).readAsStringSync(), 'frame');
        expect(File(purged[0].processedPath!).readAsStringSync(), 'warp');
        expect(File(purged[0].restoredPath).readAsStringSync(), 'enhanced');
      });

      test('a page whose files cannot be copied keeps its row until they can',
          () {
        // Say the phone has run out of space, which is when Android trims
        // caches: the frame is copied, the enhanced output is not.
        final enhanced = '$frame.enhanced.jpg';
        Process.runSync('chmod', <String>['000', enhanced]);
        final pages = migrate();
        expect(pages[0].originalPath, frame,
            reason: 'its cache paths still work while the files are there');
        expect(pages[0].processedPath, '$frame.page.jpg');
        expect(p.isWithin(root.path, pages[3].processedPath!), isTrue,
            reason: 'the other pages carry on');
        expect(version(), 2, reason: 'so the next launch tries it again');

        Process.runSync('chmod', <String>['644', enhanced]);
        final again = migrate();
        expect(p.isWithin(root.path, again[0].originalPath), isTrue);
        expect(File(again[0].originalPath).readAsStringSync(), 'frame');
        expect(File(again[0].restoredPath).readAsStringSync(), 'enhanced');
        expect(version(), 3);
      });

      test('never overwrites a file already at the name it would use', () {
        // A torn copy as long as the frame, and a different file at the next
        // name: only the bytes tell them apart from the migration's own.
        final folder = ScanStorage(root).directoryFor(1).path;
        final torn = File(p.join(folder, '1-byrsa-1.jpg'))
          ..writeAsStringSync('fram_');
        final other = File(p.join(folder, '1.1-byrsa-1.jpg'))
          ..writeAsStringSync('other');

        final page = migrate().first;
        expect(torn.readAsStringSync(), 'fram_');
        expect(other.readAsStringSync(), 'other');
        expect(page.originalPath, p.join(folder, '1.2-byrsa-1.jpg'));
        expect(File(page.originalPath).readAsStringSync(), 'frame');
        expect(File(page.processedPath!).readAsStringSync(), 'warp');
        expect(File(page.restoredPath).readAsStringSync(), 'enhanced');
      });
    });
  });

  group('word boxes', () {
    test('round-trip, so an exported PDF is genuinely searchable', () {
      final id = db.createDocument('Factura');
      final pageId = db.addPage(id, originalPath: 'a.jpg');
      db.setPageOcr(pageId, 'Total 12,40', const <PageWord>[
        PageWord(text: 'Total', left: 100, top: 200, right: 220, bottom: 240),
        PageWord(text: '12,40', left: 232, top: 200, right: 360, bottom: 240),
      ]);

      final page = db.pagesOf(id).single;
      expect(page.text, 'Total 12,40');
      expect(page.hasWordBoxes, isTrue);
      expect(page.words.map((w) => w.text), <String>['Total', '12,40']);
      expect(page.words.first.right, 220);
    });

    test('a page recognised without boxes is honest about it', () {
      // Text alone gives search inside the application and an image-only PDF
      // outside it. The distinction has to be visible, not inferred.
      final id = db.createDocument('Factura');
      final pageId = db.addPage(id, originalPath: 'a.jpg');
      db.setPageText(pageId, 'Total 12,40');

      final page = db.pagesOf(id).single;
      expect(page.hasText, isTrue);
      expect(page.hasWordBoxes, isFalse);
    });

    test('are searchable through FTS like any other page text', () {
      final id = db.createDocument('Factura');
      final pageId = db.addPage(id, originalPath: 'a.jpg');
      db.setPageOcr(pageId, 'Facturación mensual', const <PageWord>[
        PageWord(
          text: 'Facturación',
          left: 0,
          top: 0,
          right: 10,
          bottom: 10,
        ),
      ]);
      expect(db.search('facturacion'), hasLength(1));
    });
  });

  group('folders', () {
    test('nest, and list their own contents only', () {
      final parent = db.createFolder('Casa');
      final child = db.createFolder('Facturas', parentId: parent);
      expect(db.folders().map((f) => f.name), <String>['Casa']);
      expect(db.folders(parentId: parent).map((f) => f.name),
          <String>['Facturas']);

      final documentId = db.createDocument('Luz', folderId: child);
      expect(db.documents(folderId: child).single.id, documentId);
      expect(db.documents(), isEmpty,
          reason: 'the root must not show nested documents');
    });

    test('deleting a folder does not delete the documents in it', () {
      // Losing a folder is an accident; losing the scans inside it is a
      // disaster. The documents fall back to the root.
      final folder = db.createFolder('Temporal');
      final documentId = db.createDocument('Importante', folderId: folder);
      db.deleteFolder(folder);
      expect(db.document(documentId), isNotNull);
      expect(db.documents().single.id, documentId);
    });
  });

  group('schema 2 -> 3 on a disk that fails', () {
    late Directory root;
    late Directory cache;
    late Database raw;
    late String frame;
    setUp(() {
      root = Directory.systemTemp.createTempSync('byrsa_root');
      cache = Directory.systemTemp.createTempSync('byrsa_cache');
      frame = (File(p.join(cache.path, 'byrsa-1.jpg'))
            ..writeAsStringSync('frame'))
          .path;
      File('$frame.enhanced.jpg').writeAsStringSync('enhanced');
      raw = sqlite3.openInMemory();
      LibraryDatabase(raw);
      raw.execute('PRAGMA user_version = 2');
      raw.execute(
          "INSERT INTO documents(title, created_at, updated_at) VALUES ('E', 0, 0)");
      raw.execute(
          'INSERT INTO pages(document_id, position, original_path, restored) '
          'VALUES (1, 0, ?, 1)',
          <Object?>[frame]);
    });
    tearDown(() {
      raw.dispose();
      Process.runSync('chmod', <String>['-R', 'u+rwx', cache.path]);
      root.deleteSync(recursive: true);
      cache.deleteSync(recursive: true);
    });
    int version() =>
        raw.select('PRAGMA user_version').first['user_version'] as int;
    String migrate() => LibraryDatabase(raw, storage: ScanStorage(root))
        .pagesOf(1)
        .single
        .originalPath;

    test('a disk that fills mid-copy costs that page until the next launch',
        () {
      // A staging file that is /dev/full makes the copy fail with a real
      // ENOSPC, a plain FileSystemException rather than an access error.
      final folder = ScanStorage(root).directoryFor(1)
        ..createSync(recursive: true);
      Link(p.join(folder.path, '1-byrsa-1.jpg.enhanced.jpg.part'))
          .createSync('/dev/full');
      expect(migrate(), frame);
      expect(version(), 2);
      expect(migrate(), p.join(folder.path, '1-byrsa-1.jpg'));
      expect(version(), 3);
    }, skip: Platform.isLinux ? false : 'needs /dev/full');

    test('a source unreadable where its copy already exists', () {
      final folder = ScanStorage(root).directoryFor(1)
        ..createSync(recursive: true);
      File(p.join(folder.path, '1-byrsa-1.jpg')).writeAsStringSync('frame');
      Process.runSync('chmod', <String>['000', frame]);
      expect(migrate(), frame);
      expect(version(), 2);
    });
  });
}
