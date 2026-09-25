// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';

import '../domain/document.dart';
import 'scan_storage.dart';

/// The document library: folders, documents, pages, and full-text search.
///
/// Plain SQL over `sqlite3`, with a small migration runner. There is no ORM and
/// no code generation, because full-text search needs raw SQL anyway, the
/// schema is four tables, and a build step that rewrites files in the
/// repository is exactly what a reproducible F-Droid build does not want
/// (DECISIONS.md D-022).
///
/// Paths are stored **relative** to the root of the [storage] the caller
/// supplies, and every method hands them back absolute. An application whose
/// database hard-codes absolute paths breaks the first time the platform moves
/// its sandbox, and it cannot be moved into an encrypted store later without a
/// migration (D-015). This docstring said so from the start while capture and
/// import stored absolute paths into the cache; schema 3 makes it true
/// (D-056). A path outside the root is stored as given and works for as long
/// as its file exists; the migration leaves one only on a page whose copy
/// failed, and tries that page again on the next launch.
class LibraryDatabase {
  LibraryDatabase(this._db, {this.storage}) {
    _migrate();
  }

  final CommonDatabase _db;

  /// Where the scans live and what stored paths are relative to. Without one,
  /// paths are stored as given and nothing is copied, which only suits a
  /// database whose paths name no real file.
  final ScanStorage? storage;

  static const int schemaVersion = 3;

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON');
    final current =
        _db.select('PRAGMA user_version').first['user_version'] as int;
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
          restored       INTEGER NOT NULL DEFAULT 0,
          quad           TEXT,
          text           TEXT,
          words          TEXT,
          width          INTEGER,
          height         INTEGER
        );
      ''');
      // Preferences live here rather than in a separate store: the database is
      // already open, already travels with the documents, and a key-value table
      // is less machinery than another dependency.
      _db.execute('''
        CREATE TABLE settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
      _db.execute(
          'CREATE INDEX pages_document ON pages(document_id, position)');
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
    if (current < 2) {
      // `processed_path` used to hold the rectified page until restoration
      // overwrote it with its own output, `<original>.restored.jpg`, after
      // which the row no longer named the rectified page (D-051). Each such
      // row is pointed at the best picture of the page still on disk, and
      // `restored = 0` queues it to be enhanced once more from that:
      //
      // 1. `<original>.page.jpg`, the warp. Android capture writes it under
      //    that name (CaptureSession.kt:239), and the re-warp after "adjust
      //    corners" is written that way in both sources (CaptureSession.kt:256,
      //    CaptureSession.swift:244). iOS capture is not: the Swift source
      //    names its warp from a fresh timestamp (CaptureSession.swift:221,
      //    :250) and has never been compiled (U-01), so on iOS only a
      //    re-warped page would be found here.
      // 2. Otherwise nothing, so restoration starts from the original frame,
      //    as it does for a gallery import, which never had a warp. A capture
      //    whose warp alone was purged loses its crop this way, and the v1
      //    output that still holds it is left unreferenced: restoring from it
      //    would bring the compounding back, and nothing in the row says
      //    whether the page was captured or imported.
      // 3. Otherwise the v1 output is left where it is. When the OS cache
      //    purge has taken the original and its warp, it is the only picture
      //    of the page there is, and dropping it would strand it.
      //
      // The paths are checked as stored, which at schema 1 meant absolute:
      // capture and import stored what the plugin and image_picker returned.
      // Schema 3 makes them relative, after this step (D-056).
      final rows = _db.select(
        'SELECT id, original_path, processed_path FROM pages '
        "WHERE processed_path LIKE '%.restored.jpg'",
      );
      for (final row in rows) {
        final original = row['original_path'] as String;
        final warp = '$original.page.jpg';
        _db.execute(
          'UPDATE pages SET processed_path = ?, restored = 0 WHERE id = ?',
          <Object?>[
            File(warp).existsSync()
                ? warp
                : File(original).existsSync()
                    ? null
                    : row['processed_path'],
            row['id'],
          ],
        );
      }
    }
    // A page whose files could not be copied keeps the version at 2, so the
    // next launch tries it again.
    final kept = storage == null || _keepCachedFiles(storage!);
    final version = kept ? schemaVersion : 2;
    // Unchanged, it is not written: on a full disk even that write can fail.
    if (version != current) _db.execute('PRAGMA user_version = $version');
  }

  /// Schema 2 -> 3: copies every page's files out of the platform cache and
  /// stores the paths relative to the root (D-056). Returns whether every page
  /// made it.
  ///
  /// Up to schema 2 the only copy of every scan was where capture and
  /// image_picker wrote it, a cache the OS may empty. Every path outside the
  /// root — the original, what `processed_path` names, and
  /// `<original>.enhanced.jpg`, so a restored page keeps its restoration and
  /// is not queued again — moves to `<page id>-<name>` in its document's
  /// folder. A warp and an enhanced output named after the original stay named
  /// after it, so the `<original>.page.jpg` and `.enhanced.jpg` conventions
  /// hold at the new place too. A path whose file is already gone moves as
  /// well: it named nothing and still does, but what is derived from the
  /// original — a surviving enhanced output, every later restoration — lands
  /// in storage, and a copy an earlier run made before the OS purged its
  /// source is found at that name.
  ///
  /// Each copy is written as `<name>.part` and then renamed, so a file at a
  /// page's name is always whole; a copy cut short leaves only its `.part`,
  /// which a later attempt overwrites and deleting the document removes.
  /// Nothing a row can name is deleted or overwritten. A name already taken by
  /// different bytes moves the page to `<page id>.1-<name>` and on; the same
  /// bytes are this migration's own copy from a run that did not reach its
  /// row, and are used as they are. That is what makes running it again
  /// harmless. The cache files stay for the OS to purge.
  ///
  /// A page whose copies fail — no space left, which is when Android trims
  /// caches, or a file purged mid-copy — keeps its row exactly as it was,
  /// which works for as long as its files exist, and the other pages carry on.
  ///
  /// TODO: copies synchronously on the UI isolate the first time the library
  /// opens, so a library of many cached pages freezes the first screen for as
  /// long as the copies take; run it in an isolate behind a progress screen if
  /// a real library shows that.
  bool _keepCachedFiles(ScanStorage storage) {
    final root = storage.root.path;
    bool outside(String? path) =>
        path != null && p.isAbsolute(path) && !p.isWithin(root, path);
    bool exists(String path) => File(path).existsSync();

    var everyPage = true;
    final rows = _db.select(
      'SELECT id, document_id, original_path, processed_path FROM pages',
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final original = row['original_path'] as String;
      final processed = row['processed_path'] as String?;
      final directory = storage.directoryFor(row['document_id'] as int).path;
      final moving = <String>{
        if (outside(original)) ...<String>[original, '$original.enhanced.jpg'],
        if (outside(processed)) processed!,
      };

      var attempt = 0;
      String target(String source) => p.join(directory,
          '$id${attempt == 0 ? '' : '.$attempt'}-${p.basename(source)}');
      try {
        while (moving.any((source) =>
            exists(source) &&
            exists(target(source)) &&
            !_sameBytes(source, target(source)))) {
          attempt++;
        }
        for (final source in moving) {
          if (!exists(source) || exists(target(source))) continue;
          Directory(directory).createSync(recursive: true);
          File(source).copySync('${target(source)}.part');
          File('${target(source)}.part').renameSync(target(source));
        }

        String? kept(String? path) =>
            _toStored(moving.contains(path) ? target(path!) : path);
        // A retry rewrites only what moves, since every write needs a journal
        // and a full disk has no room for one; a row that cannot be written
        // (SQLITE_FULL) is left for the next launch like a failed copy.
        if (kept(original) != original || kept(processed) != processed) {
          _db.execute(
            'UPDATE pages SET original_path = ?, processed_path = ? WHERE id = ?',
            <Object?>[kept(original), kept(processed), id],
          );
        }
      } on Exception {
        everyPage = false;
      }
    }
    return everyPage;
  }

  static bool _sameBytes(String a, String b) {
    if (File(a).lengthSync() != File(b).lengthSync()) return false;
    final x = File(a).readAsBytesSync();
    final y = File(b).readAsBytesSync();
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  /// What a path is stored as: relative when it is under the root, as given
  /// otherwise.
  String? _toStored(String? path) {
    final root = storage?.root.path;
    if (path == null || root == null || p.isRelative(path)) return path;
    return p.isWithin(root, path) ? p.relative(path, from: root) : path;
  }

  /// What every caller is handed: an absolute path, wherever the root is now.
  String? _fromStored(String? path) {
    final root = storage?.root.path;
    if (path == null || root == null || p.isAbsolute(path)) return path;
    return p.join(root, path);
  }

  // ---- Settings ----

  String? setting(String key) {
    final rows = _db.select(
      'SELECT value FROM settings WHERE key = ?',
      <Object?>[key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) {
    _db.execute(
      'INSERT INTO settings(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      <Object?>[key, value],
    );
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
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
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

  /// Adds a page, copying its files out of the cache into [storage] first.
  ///
  /// What capture and gallery import call. Both hand over files in the
  /// platform cache, which the OS may empty, so the row is written only once
  /// the copies exist: a copy that fails throws before the library can point
  /// at a file it does not own. The warp is kept beside the frame as
  /// `<frame>.page.jpg`, the name the re-warp after "adjust corners" writes and
  /// the D-051 migration looks for.
  Future<int> keepPage(
    int documentId, {
    required String originalPath,
    String? rectifiedPath,
    List<double>? quad,
    int? width,
    int? height,
  }) async {
    final original = await storage!.keep(originalPath, documentId: documentId);
    // A warp the OS already purged costs the crop, not the page: restoration
    // falls back to the frame, and the stored quad lets "adjust corners" warp
    // it again.
    final rectified = rectifiedPath == null || !File(rectifiedPath).existsSync()
        ? null
        : (await File(rectifiedPath).copy('$original.page.jpg')).path;
    return addPage(
      documentId,
      originalPath: original,
      processedPath: rectified,
      quad: quad,
      width: width,
      height: height,
    );
  }

  int addPage(
    int documentId, {
    required String originalPath,
    String? processedPath,
    String? text,
    List<PageWord> words = const <PageWord>[],
    List<double>? quad,
    int? width,
    int? height,
  }) {
    final next = _db.select(
      'SELECT COALESCE(MAX(position) + 1, 0) AS next FROM pages WHERE document_id = ?',
      <Object?>[documentId],
    ).first['next'] as int;

    // `quad` and `words` are in the column list because they once were not:
    // the corners detected at capture were accepted as an argument and thrown
    // away, so "adjust corners" always opened on the full frame rather than on
    // what the detector had found.
    _db.execute(
      'INSERT INTO pages(document_id, position, original_path, processed_path, '
      'quad, text, words, width, height) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        documentId,
        next,
        _toStored(originalPath),
        _toStored(processedPath),
        quad == null ? null : jsonEncode(quad),
        text,
        _encodeWords(words),
        width,
        height
      ],
    );
    _touch(documentId);
    return _db.lastInsertRowId;
  }

  /// Stores the result of recognising a page.
  ///
  /// Text and word boxes are written together, always: a page with text but no
  /// boxes searches inside the application and exports an image-only PDF, and
  /// discovering that months later is worse than not having recognised it.
  void setPageOcr(int pageId, String text, List<PageWord> words) {
    _db.execute(
      'UPDATE pages SET text = ?, words = ? WHERE id = ?',
      <Object?>[text, _encodeWords(words), pageId],
    );
  }

  /// Text only, for a caller that has no boxes to offer.
  void setPageText(int pageId, String text) {
    _db.execute('UPDATE pages SET text = ? WHERE id = ?', <Object?>[
      text,
      pageId,
    ]);
  }

  /// Records a page that has been through restoration.
  ///
  /// A flag and no path: where the restored image lives is
  /// [ScanPage.restoredPath], a convention on the original frame. This method
  /// used to take the path and write it into `processed_path`, which destroyed
  /// the only reference to the rectified page and made every later
  /// re-restoration read its own previous output.
  void setPageRestored(int pageId) {
    _db.execute(
      'UPDATE pages SET restored = 1 WHERE id = ?',
      <Object?>[pageId],
    );
  }

  /// Queues every page of a document to be restored again.
  ///
  /// What a filter change is: the rectified page is untouched and still the
  /// input, only the enhancement that runs over it differs.
  void setPagesNeedRestore(int documentId) => _db.execute(
        'UPDATE pages SET restored = 0 WHERE document_id = ?',
        <Object?>[documentId],
      );

  /// Records a new warp of a page, from new corners.
  ///
  /// Clears the restored flag on purpose: the old restored image described a
  /// different rectangle, so the page goes back into the queue.
  void setPageProcessed(int pageId, String processedPath,
      {List<double>? quad}) {
    _db.execute(
      'UPDATE pages SET processed_path = ?, restored = 0'
      '${quad == null ? '' : ', quad = ?'} WHERE id = ?',
      <Object?>[
        _toStored(processedPath),
        if (quad != null) jsonEncode(quad),
        pageId
      ],
    );
  }

  void deletePage(int pageId) =>
      _db.execute('DELETE FROM pages WHERE id = ?', <Object?>[pageId]);

  List<ScanPage> pagesOf(int documentId) => _db
      .select(
        'SELECT id, document_id, position, original_path, processed_path, '
        'restored, quad, text, words, width, height '
        'FROM pages WHERE document_id = ? ORDER BY position',
        <Object?>[documentId],
      )
      .map((row) => ScanPage(
            id: row['id'] as int,
            documentId: row['document_id'] as int,
            position: row['position'] as int,
            originalPath: _fromStored(row['original_path'] as String)!,
            processedPath: _fromStored(row['processed_path'] as String?),
            restored: (row['restored'] as int? ?? 0) != 0,
            quad: _decodeQuad(row['quad'] as String?),
            text: row['text'] as String?,
            words: _decodeWords(row['words'] as String?),
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

  static List<double>? _decodeQuad(String? json) {
    if (json == null || json.isEmpty) return null;
    final values = (jsonDecode(json) as List).cast<num>();
    return values.length == 8
        ? values.map((v) => v.toDouble()).toList(growable: false)
        : null;
  }

  static String? _encodeWords(List<PageWord> words) =>
      words.isEmpty ? null : jsonEncode(words.map((w) => w.toJson()).toList());

  static List<PageWord> _decodeWords(String? json) {
    if (json == null || json.isEmpty) return const <PageWord>[];
    return (jsonDecode(json) as List)
        .cast<Map<String, Object?>>()
        .map(PageWord.fromJson)
        .toList(growable: false);
  }

  void _touch(int documentId) {
    _db.execute(
      'UPDATE documents SET updated_at = ? WHERE id = ?',
      <Object?>[DateTime.now().millisecondsSinceEpoch, documentId],
    );
  }

  void dispose() => _db.dispose();
}
