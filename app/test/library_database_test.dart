// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa/src/data/library_database.dart';
import 'package:byrsa/src/domain/document.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(LibraryDatabase.schemaVersion, 2);
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
}
