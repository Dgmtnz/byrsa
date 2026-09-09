// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../data/preferences.dart';
import '../data/providers.dart';

/// Capture: preview, live outline, batch of pages, save as a document.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  late final ByrsaCaptureController _controller = ByrsaCaptureController(
    autoCapture: ref.read(preferencesProvider).autoCapture,
  );
  CameraPermissionDenied? _denied;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _denied = null;
      _error = null;
    });
    try {
      await _controller.start();
    } on CameraPermissionDenied catch (denied) {
      if (mounted) setState(() => _denied = denied);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scan),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => TextButton(
              onPressed: _controller.pages.isEmpty || _saving ? null : _save,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
      body: switch ((_denied, _error)) {
        (final CameraPermissionDenied denied, _) => _PermissionNotice(
            denied: denied,
            onRetry: _start,
          ),
        (_, final Object error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$error', textAlign: TextAlign.center),
            ),
          ),
        _ => CapturePreview(
            controller: _controller,
            hintBuilder: (context, hint) => _hint(hint),
          ),
      },
      floatingActionButton: _denied != null || _error != null
          ? null
          : FloatingActionButton(
              onPressed: _controller.capture,
              child: const Icon(Icons.camera),
            ),
    );
  }

  /// The guidance line, translated. The package ships English wording and this
  /// hook so an application does not inherit somebody else's localisation.
  String _hint(CaptureHint hint) => switch (hint) {
        CaptureHint.noDocument => 'Apunta a un documento',
        CaptureHint.tooFar => 'Acércate',
        CaptureHint.cropped => 'Encuadra la página entera',
        CaptureHint.moving => 'No te muevas',
        CaptureHint.blurry => 'Enfocando…',
        CaptureHint.tooDark => 'Falta luz',
        CaptureHint.ready => 'Listo',
      };

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final library = await ref.read(libraryProvider.future);
      final title =
          'Escaneo ${DateTime.now().toIso8601String().substring(0, 16)}';
      final documentId = library.createDocument(title);
      for (final page in _controller.pages) {
        library.addPage(
          documentId,
          originalPath: page.originalPath,
          processedPath: page.rectifiedPath,
          quad: <double>[
            for (final corner in page.quad.corners) ...<double>[
              corner.x,
              corner.y
            ],
          ],
          width: page.width,
          height: page.height,
        );
      }
      ref.read(libraryRevisionProvider.notifier).state++;
      if (mounted) context.go('/document/$documentId');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Explains why the camera is needed, and offers the only action that can
/// actually help.
///
/// The two cases are genuinely different: one deserves a retry, the other a
/// trip to Settings. An interface that offers "try again" after a permanent
/// refusal just looks broken.
class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.denied, required this.onRetry});

  final CameraPermissionDenied denied;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.no_photography_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              l10n.cameraNeeded,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              denied.permanently
                  ? l10n.cameraDeniedBody
                  : l10n.cameraNeededBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!denied.permanently)
              FilledButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
          ],
        ),
      ),
    );
  }
}
