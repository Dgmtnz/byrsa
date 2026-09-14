// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spanish a human wrote: letters English never uses, plus words that are
/// unmistakably interface text rather than a column name or an identifier.
///
/// The word list is deliberately short. A guard that cries wolf gets deleted,
/// and one confident marker per string is enough to catch the mistake this is
/// about — a sentence typed straight into a widget.
final RegExp _spanish = RegExp(
  '[áéíóúñüÁÉÍÓÚÑÜ¿¡]|'
  r'\b(importado|importada|escaneo|escanear|escaneando|pagina|paginas|'
  r'guardar|cancelar|borrar|eliminar|carpeta|documentos?|ajustes|buscar|'
  r'compartir|descargar|renombrar|reintentar|aceptar|siguiente|anterior)\b',
  caseSensitive: false,
);

/// A single-line Dart string literal. Comments are cut off first, so an
/// apostrophe in English prose cannot be mistaken for one.
final RegExp _literal = RegExp('\'[^\'\n]*\'|"[^"\n]*"');

void main() {
  test('no Spanish is hard-coded outside the translation files', () {
    // The first run on a real phone showed an English library handing over to
    // a camera that said "Apunta a un documento": seven guidance strings and
    // every scan title were Spanish literals in Dart. No test caught it, and
    // none could — a widget test renders whatever the source says and then
    // asserts on that same wording, so it agrees with the bug. The only thing
    // that sees this is reading the source, which is what this does.
    final Directory lib =
        Directory('lib').existsSync() ? Directory('lib') : Directory('app/lib');
    expect(lib.existsSync(), isTrue,
        reason: 'run from the app package or from the repository root');

    final offenders = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // lib/l10n holds the translations themselves, generated from the .arb
      // files. Spanish is the point there.
      if (entity.path.contains('${Platform.pathSeparator}l10n'
          '${Platform.pathSeparator}')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        for (final match in _literal.allMatches(code)) {
          if (_spanish.hasMatch(match.group(0)!)) {
            offenders.add('${entity.path}:${i + 1}  ${match.group(0)}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'put these in app_en.arb and app_es.arb and read them back '
            'through AppLocalizations.of(context)!:\n${offenders.join('\n')}');
  });
}
