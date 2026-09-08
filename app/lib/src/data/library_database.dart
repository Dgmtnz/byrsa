// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:sqlite3/common.dart';

import '../domain/document.dart';

/// The document library: folders, documents, pages, and full-text search.
///
/// Plain SQL over `sqlite3`, with a small migration runner. There is no ORM and
/// no code generation, because full-text search needs raw SQL anyway, the
/// schema is four tables, and a build step that rewrites files in the
/// repository is exactly what a reproducible F-Droid build does not want
/// (DECISIONS.md D-022).
///
/// Paths are stored **relative** to a root directory the caller supplies. An
/// application whose database hard-codes absolute paths breaks the first time
/// the platform moves its sandbox, and it cannot be moved into an encrypted
/// store later without a migration (D-015).
class LibraryDatabase {
  LibraryDatabase(this._db) {
    _migrate();
  }

  final CommonDatabase _db;

  static const int schemaVersion = 1;

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON');
    final current = _db.select('PRAGMA user_version').first['user_version'] as int;
    if (current >= schemaVersion) return;

    if (current < 1) {
      _db.execute('''
        CREATE TABLE folders (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          name      TEXT NOT NULL,
          parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE documents (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          title      TEXT NOT NULL,
          folder_id  INTEGER REFERENCES folders(id) ON DELETE SET NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        CREATE TABLE pages (
          id             INTEGER PRIMARY KEY AUTOINCREMENT,
          document_id    INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          position       INTEGER NOT NULL,
          original_path  TEXT NOT NULL,
          processed_path TEXT,
          text           TEXT,
          width          INTEGER,
          height         INTEGER
        );
      ''');
      _db.execute('CREATE INDEX pages_document ON pages(document_id, position)');
      _db.execute('CREATE INDEX documents_folder ON documents(folder_id)');

      // External-content FTS: the index holds no copy of the text, so a page
      // and its index cannot disagree, and the database does not store every
      // scan twice.
      _db.execute('''
        CREATE VIRTUAL TABLE pages_fts USING fts5(
          text,
          content = 'pages',
          content_rowid = 'id',
          tokenize = "unicode61 remove_diacritics 2"
        );
      ''');
      for (final trigger in <String>[
        '''CREATE TRIGGER pages_ai AFTER INSERT ON pages BEGIN
             INSERT INTO pages_fts(rowid, text) VALUES (new.id, new.text);
           END;''',
        '''CREATE TRIGGER pages_ad AFTER DELETE ON pages BEGIN
             INSERT INTO pages_fts(pages_fts, rowid, text) VALUES('delete', old.id, old.text);
           END;''',
        '''CREATE TRIGGER pages_au AFTER UPDATE ON pages BEGIN
             INSERT INTO pages_fts(pages_fts, rowid, text) VALUES('delete', old.id, old.text);
             INSERT INTO pages_fts(rowid, text) VALUES (new.id, new.text);
           END;''',
      ]) {
        _db.execute(trigger);
      }
    }
    _db.execute('PRAGMA user_version = $schemaVersion');
  }

  // ---- Folders ----

  int createFolder(String name, {int? parentId}) {
    _db.execute(
      'INSERT INTO folders(name, parent_id) VALUES (?, ?)',
      <Object?>[name, parentId],
    );
    return _db.lastInsertRowId;
  }

  List<Folder> folders({int? parentId}) => _db
      .select(
        'SELECT id, name, parent_id FROM folders '
        'WHERE parent_id IS ? ORDER BY name COLLATE NOCASE',
        <Object?>[parentId],
      )
      .map((row) => Folder(
            id: row['id'] as int,
            name: row['name'] as String,
            parentId: row['parent_id'] as int?,
          ))
      .toList();

  void deleteFolder(int id) =>
      _db.execute('DELETE FROM folders WHERE id = ?', <Object?>[id]);

  // ---- Documents ----

  int createDocument(String title, {int? folderId, DateTime? now}) {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _db.execute(
      'INSERT INTO documents(title, folder_id, created_at, updated_at) VALUES (?, ?, ?, ?)',
      <Object?>[title, folderId, stamp, stamp],
    );
    return _db.lastInsertRowId;
  }

  void renameDocument(int id, String title) {
    _db.execute(
      'UPDATE documents SET title = ?, updated_at = ? WHERE id = ?',
      <Object?>[title, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  void moveDocument(int id, int? folderId) {
    _db.execute(
      'UPDATE documents SET folder_id = ?, updated_at = ? WHERE id = ?',
      <Object?>[folderId, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  void deleteDocument(int id) =>
      _db.execute('DELETE FROM documents WHERE id = ?', <Object?>[id]);

  List<ScanDocument> documents({int? folderId, bool withPages = false}) {
    final rows = _db.select(
      'SELECT id, title, folder_id, created_at, updated_at FROM documents '
      'WHERE folder_id IS ? ORDER BY updated_at DESC',
      <Object?>[folderId],
    );
    return rows.map((row) {
      final id = row['id'] as int;
      return ScanDocument(
        id: id,
        title: row['title'] as String,
        folderId: row['folder_id'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        pages: withPages ? pagesOf(id) : const <ScanPage>[],
      );
    }).toList();
  }

  ScanDocument? document(int id) {
    final rows = _db.select(
      'SELECT id, title, folder_id, created_at, updated_at FROM documents WHERE id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ScanDocument(
      id: id,
      title: row['title'] as String,
      folderId: row['folder_id'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      pages: pagesOf(id),
    );
  }

  // ---- Pages ----

  int addPage(
    int documentId, {
    required String originalPath,
    String? processedPath,
    String? text,
    int? width,
    int? height,
  }) {
    final next = _db.select(
      'SELECT COALESCE(MAX(position) + 1, 0) AS next FROM pages WHERE document_id = ?',
      <Object?>[documentId],
    ).first['next'] as int;

    _db.execute(
      'INSERT INTO pages(document_id, position, original_path, processed_path, text, width, height) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[documentId, next, originalPath, processedPath, text, width, height],
    );
    _touch(documentId);
    return _db.lastInsertRowId;
  }

  void setPageText(int pageId, String text) {
    _db.execute('UPDATE pages SET text = ? WHERE id = ?', <Object?>[text, pageId]);
  }

  void setPageProcessed(int pageId, String processedPath) {
    _db.execute(
      'UPDATE pages SET processed_path = ? WHERE id = ?',
      <Object?>[processedPath, pageId],
    );
  }

  void deletePage(int pageId) =>
      _db.execute('DELETE FROM pages WHERE id = ?', <Object?>[pageId]);

  List<ScanPage> pagesOf(int documentId) => _db
      .select(
        'SELECT id, document_id, position, original_path, processed_path, text, width, height '
        'FROM pages WHERE document_id = ? ORDER BY position',
        <Object?>[documentId],
      )
      .map((row) => ScanPage(
            id: row['id'] as int,
            documentId: row['document_id'] as int,
            position: row['position'] as int,
            originalPath: row['original_path'] as String,
            processedPath: row['processed_path'] as String?,
            text: row['text'] as String?,
            width: row['width'] as int?,
            height: row['height'] as int?,
          ))
      .toList();

  /// Rewrites page order in one transaction, so an interrupted reorder cannot
  /// leave two pages claiming the same position.
  void reorderPages(int documentId, List<int> pageIdsInOrder) {
    _db.execute('BEGIN');
    try {
      for (var i = 0; i < pageIdsInOrder.length; i++) {
        _db.execute(
          'UPDATE pages SET position = ? WHERE id = ? AND document_id = ?',
          <Object?>[i, pageIdsInOrder[i], documentId],
        );
      }
      _db.execute('COMMIT');
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _touch(documentId);
  }

  // ---- Search ----

  /// Full-text search across every page.
  ///
  /// Accent-insensitive, because "factura" and "Facturación" must both find a
  /// Spanish invoice and nobody types accents into a search box.
  List<SearchHit> search(String query, {int limit = 50}) {
    final match = _toMatchQuery(query);
    if (match == null) return const <SearchHit>[];
    return _db
        .select(
          '''
          SELECT d.id AS document_id, d.title AS title, p.position AS position,
                 snippet(pages_fts, 0, '[', ']', '…', 12) AS snippet
          FROM pages_fts
          JOIN pages p ON p.id = pages_fts.rowid
          JOIN documents d ON d.id = p.document_id
          WHERE pages_fts MATCH ?
          ORDER BY bm25(pages_fts)
          LIMIT ?
          ''',
          <Object?>[match, limit],
        )
        .map((row) => SearchHit(
              documentId: row['document_id'] as int,
              title: row['title'] as String,
              snippet: row['snippet'] as String,
              pagePosition: row['position'] as int,
            ))
        .toList();
  }

  /// Turns what a person typed into an FTS5 query.
  ///
  /// Every term is quoted and given a prefix `*`, so a search behaves like
  /// search-as-you-type and a stray `"` or `*` cannot become a syntax error the
  /// user has to understand.
  static String? _toMatchQuery(String query) {
    final terms = query
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll('"', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;
    return terms.map((t) => '"$t"*').join(' AND ');
  }

  void _touch(int documentId) {
    _db.execute(
      'UPDATE documents SET updated_at = ? WHERE id = ?',
      <Object?>[DateTime.now().millisecondsSinceEpoch, documentId],
    );
  }

  void dispose() => _db.dispose();
}
