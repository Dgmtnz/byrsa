// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter_test/flutter_test.dart';

/// The repository's real manifest, so these tests fail when it drifts.
///
/// Found by walking up from wherever the test runner started, because that
/// differs between running one package and running the workspace.
ModelCatalog realCatalog() {
  var directory = Directory.current;
  for (var i = 0; i < 5; i++) {
    final file = File('${directory.path}/models.json');
    if (file.existsSync()) return ModelCatalog.parse(file.readAsStringSync());
    directory = directory.parent;
  }
  throw StateError('models.json not found above ${Directory.current.path}');
}

void main() {
  group('the repository manifest', () {
    test('pins every file of every model it would ship', () {
      for (final model in realCatalog().models.values) {
        if (!model.usable) continue;
        for (final file in model.files) {
          expect(
            file.isPinned,
            isTrue,
            reason: '${model.id}/${file.fileName} has no SHA-256',
          );
        }
      }
    });

    test('records why a rejected model was rejected', () {
      // "We measured this and rejected it" is more useful to the next person
      // than an absence, but only if the reason travels with it.
      for (final model in realCatalog().models.values) {
        if (model.usable) continue;
        expect(model.notUsableReason, isNotNull, reason: model.id);
        expect(model.notUsableReason, contains('Measured'), reason: model.id);
      }
    });

    test('knows UVDoc comes as two files whose names matter', () {
      // The .onnx references its weights sidecar by file name. Store it as
      // uvdoc-grid.onnx and the model stops loading, with an error that does
      // not mention the renaming.
      final model = realCatalog()['uvdoc-grid'];
      expect(model.files, hasLength(2));
      expect(model.primary.fileName, 'UVDoc_grid.onnx');
      expect(model.files.last.fileName, 'UVDoc_grid.onnx.data');
      expect(model.sizeBytes, greaterThan(30 * 1024 * 1024));
    });
  });

  group('parsing', () {
    test('accepts the short form for a single-file model', () {
      final catalog = ModelCatalog.parse(jsonEncode({
        'models': [
          {
            'id': 'small',
            'url': 'https://example.invalid/small.onnx',
            'sizeBytes': 10,
            'sha256': 'a' * 64,
            'license': 'MIT',
          }
        ]
      }));
      expect(catalog['small'].files, hasLength(1));
      expect(catalog['small'].primary.fileName, 'small.onnx');
    });

    test('adds up the size of every file, which is what the user pays', () {
      final catalog = ModelCatalog.parse(jsonEncode({
        'models': [
          {
            'id': 'big',
            'license': 'MIT',
            'files': [
              {
                'fileName': 'a.onnx',
                'url': 'https://x/a',
                'sizeBytes': 1000,
                'sha256': 'a' * 64
              },
              {
                'fileName': 'a.onnx.data',
                'url': 'https://x/b',
                'sizeBytes': 30000,
                'sha256': 'b' * 64
              },
            ],
          }
        ]
      }));
      expect(catalog['big'].sizeBytes, 31000);
      expect(catalog['big'].isPinned, isTrue);
    });

    test('one unpinned file makes the whole model unpinned', () {
      final catalog = ModelCatalog.parse(jsonEncode({
        'models': [
          {
            'id': 'half',
            'license': 'MIT',
            'files': [
              {
                'fileName': 'a.onnx',
                'url': 'https://x/a',
                'sizeBytes': 1,
                'sha256': 'a' * 64
              },
              {'fileName': 'a.onnx.data', 'url': 'https://x/b', 'sizeBytes': 2},
            ],
          }
        ]
      }));
      expect(catalog['half'].isPinned, isFalse);
      expect(catalog.blockers.map((m) => m.id), <String>['half']);
    });
  });
}
