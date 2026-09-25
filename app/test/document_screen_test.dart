// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa/l10n/app_localizations.dart';
import 'package:byrsa/src/data/library_database.dart';
import 'package:byrsa/src/data/providers.dart';
import 'package:byrsa/src/ui/document_screen.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  testWidgets('a page whose files are gone costs that page, and only once',
      (tester) async {
    // Both pages fail, in decode, before restoration reaches the isolate that
    // `flutter test` cannot run. What is under test is the loop around it.
    final root = Directory.systemTemp.createTempSync('byrsa_document');
    addTearDown(() => root.deleteSync(recursive: true));
    final library = LibraryDatabase(sqlite3.openInMemory());
    addTearDown(library.dispose);
    final id = library.createDocument('Escaneo');
    library.addPage(id, originalPath: '${root.path}/first.jpg');
    library.addPage(id, originalPath: '${root.path}/second.jpg');

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageRootProvider.overrideWith((ref) async => root),
          // rootBundle only finds the asset when run from the app package.
          modelCatalogProvider.overrideWith((ref) async => ModelCatalog.parse(
              File(File('assets/models.json').existsSync()
                      ? 'assets/models.json'
                      : 'app/assets/models.json')
                  .readAsStringSync())),
          libraryProvider.overrideWith((ref) async => library),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentScreen(documentId: id),
        ),
      ));
      for (var frame = 0; frame < 20; frame++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(find.textContaining('second.jpg'), findsOneWidget,
        reason: 'the page after the failing one is still tried');

    // Outside `runAsync` file reads never complete, so a pass started by the
    // next frame would still be running on the one after it.
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'and neither is tried again on the next frame');
    expect(find.textContaining('second.jpg'), findsOneWidget,
        reason: 'so the error stays on screen');
  });

  testWidgets('a setup that fails is reported once, not retried every frame',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('byrsa_document');
    addTearDown(() => root.deleteSync(recursive: true));
    final library = LibraryDatabase(sqlite3.openInMemory());
    addTearDown(library.dispose);
    final id = library.createDocument('Escaneo');
    library.addPage(id, originalPath: '${root.path}/first.jpg');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageRootProvider.overrideWith((ref) async => root),
        libraryProvider.overrideWith((ref) async => library),
        modelStoreProvider
            .overrideWith((ref) async => throw StateError('no model store')),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentScreen(documentId: id),
      ),
    ));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
    }
    expect(find.textContaining('no model store'), findsOneWidget);
    // Each pass ends in setState, so a pass per frame keeps a frame scheduled.
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'the failed setup does not start another pass');
  });
}
