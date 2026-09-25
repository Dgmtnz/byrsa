// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;

/// Owns the scan files on disk.
///
/// This exists because of a bug worth naming: `byrsa_capture` writes its
/// results to the platform's **cache** directory — `context.cacheDir` on
/// Android, `NSTemporaryDirectory()` on iOS — and that is correct, because a
/// capture the user then discards should not survive. But the operating system
/// is entitled to empty those directories whenever it wants storage back, and
/// an application that keeps its only copy there loses the user's documents
/// silently, weeks later, with no error anywhere.
///
/// So the rule is: the plugin produces temporary files, and anything the
/// application decides to keep is copied here first. `LibraryDatabase.keepPage`
/// is where that happens, for capture and gallery import alike, and the
/// database stores the paths relative to [root]. Until schema 3 the rule was
/// written here and nothing called [keep]; the schema 3 migration copies in
/// what those versions left in the cache (D-056).
class ScanStorage {
  const ScanStorage(this.root);

  /// The application's own documents directory, not a cache.
  final Directory root;

  Directory directoryFor(int documentId) =>
      Directory(p.join(root.path, 'scans', '$documentId'));

  /// Copies [sourcePath] into this document's folder and returns the new path.
  ///
  /// Returns the original path unchanged if the file is already inside the
  /// store, so calling it twice is harmless.
  Future<String> keep(String sourcePath, {required int documentId}) async {
    final directory = directoryFor(documentId);
    if (p.isWithin(directory.path, sourcePath)) return sourcePath;

    await directory.create(recursive: true);
    final target = p.join(
      directory.path,
      '${DateTime.now().microsecondsSinceEpoch}${p.extension(sourcePath)}',
    );
    await File(sourcePath).copy(target);
    return target;
  }

  /// Removes every file belonging to a document.
  ///
  /// Called when the document is deleted. Without it the images stay on disk
  /// forever and the only symptom is a phone that slowly fills up.
  Future<void> discard(int documentId) async {
    final directory = directoryFor(documentId);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
