// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/document.dart';
import 'library_database.dart';

/// Where scans and the database live. Overridden in tests with a temp folder.
final storageRootProvider = FutureProvider<Directory>((ref) async {
  final directory = await getApplicationDocumentsDirectory();
  final scans = Directory(p.join(directory.path, 'scans'));
  if (!scans.existsSync()) scans.createSync(recursive: true);
  return directory;
});

final libraryProvider = FutureProvider<LibraryDatabase>((ref) async {
  final root = await ref.watch(storageRootProvider.future);
  final database =
      LibraryDatabase(sqlite3.open(p.join(root.path, 'library.db')));
  ref.onDispose(database.dispose);
  return database;
});

/// Bumped whenever the library changes, so views rebuild.
///
/// A counter rather than a stream-per-query: the library is small, the queries
/// are milliseconds, and a hand-rolled invalidation graph would be more code
/// than it saves.
final libraryRevisionProvider = StateProvider<int>((ref) => 0);

final documentsProvider =
    FutureProvider.family<List<ScanDocument>, int?>((ref, folderId) async {
  ref.watch(libraryRevisionProvider);
  final library = await ref.watch(libraryProvider.future);
  return library.documents(folderId: folderId, withPages: true);
});

final foldersProvider =
    FutureProvider.family<List<Folder>, int?>((ref, parentId) async {
  ref.watch(libraryRevisionProvider);
  final library = await ref.watch(libraryProvider.future);
  return library.folders(parentId: parentId);
});

final documentProvider =
    FutureProvider.family<ScanDocument?, int>((ref, id) async {
  ref.watch(libraryRevisionProvider);
  final library = await ref.watch(libraryProvider.future);
  return library.document(id);
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<SearchHit>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return const <SearchHit>[];
  final library = await ref.watch(libraryProvider.future);
  return library.search(query);
});

final ocrReadinessProvider = FutureProvider<OcrReadiness>((ref) async {
  ref.watch(libraryRevisionProvider);
  return const ByrsaOcr().readiness();
});
