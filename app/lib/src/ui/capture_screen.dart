// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../data/providers.dart';

/// Capture: preview, live outline, batch of pages, save as a document.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final ByrsaCaptureController _controller = ByrsaCaptureController();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller.start().catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.scan)),
        body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24), child: Text('$_error')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scan),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => TextButton(
              onPressed: _controller.pages.isEmpty ? null : _save,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
      body: CapturePreview(
        controller: _controller,
        hintBuilder: (context, hint) => _hint(l10n, hint),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _controller.capture,
        child: const Icon(Icons.camera),
      ),
    );
  }

  /// The guidance line, translated. The package ships English wording and this
  /// hook so an application does not inherit somebody else's localisation.
  String _hint(AppLocalizations l10n, CaptureHint hint) => switch (hint) {
        CaptureHint.noDocument => 'Apunta a un documento',
        CaptureHint.tooFar => 'Acércate',
        CaptureHint.cropped => 'Encuadra la página entera',
        CaptureHint.moving => 'No te muevas',
        CaptureHint.blurry => 'Enfocando…',
        CaptureHint.tooDark => 'Falta luz',
        CaptureHint.ready => 'Listo',
      };

  Future<void> _save() async {
    final library = await ref.read(libraryProvider.future);
    final title =
        'Escaneo ${DateTime.now().toIso8601String().substring(0, 16)}';
    final documentId = library.createDocument(title);
    for (final page in _controller.pages) {
      library.addPage(
        documentId,
        originalPath: page.originalPath,
        processedPath: page.rectifiedPath,
        width: page.width,
        height: page.height,
      );
    }
    ref.read(libraryRevisionProvider.notifier).state++;
    if (mounted) context.go('/document/$documentId');
  }
}
