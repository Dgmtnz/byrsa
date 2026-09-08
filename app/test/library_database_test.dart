// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa/src/data/library_database.dart';
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
      expect(LibraryDatabase.schemaVersion, 1);
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
