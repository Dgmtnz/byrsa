// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../data/image_io.dart';
import '../data/providers.dart';
import '../domain/document.dart';

/// One document: its pages, and the two exports that make a scan useful
/// somewhere else.
class DocumentScreen extends ConsumerStatefulWidget {
  const DocumentScreen({required this.documentId, super.key});

  final int documentId;

  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  String? _status;
  bool _busy = false;
  bool _restoring = false;

  /// Pages captured but not yet restored are finished off in the background as
  /// soon as the document is opened.
  ///
  /// Capture gives a perspective-corrected page immediately, which is what the
  /// user should see the instant they tap; flattening the light takes a second
  /// or two per page and has no business blocking that. So the page appears,
  /// and then visibly improves.
  Future<void> _restorePending(ScanDocument document) async {
    if (_restoring) return;
    final pending = document.pages.where((page) => !page.restored).toList();
    if (pending.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _restoring = true;
      _status = l10n.processing;
    });
    try {
      final library = await ref.read(libraryProvider.future);
      const io = ImageIo();
      for (final page in pending) {
        final outcome = await io.restoreFile(
          // Always from the perspective-corrected page, never from a previous
          // restoration: applying the correction twice compounds it.
          inputPath: page.processedPath ?? page.originalPath,
          outputPath: '${page.originalPath}.restored.jpg',
        );
        library.setPageRestored(page.id, outcome.path);
        if (mounted) ref.read(libraryRevisionProvider.notifier).state++;
      }
    } on Object catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
          if (_status == l10n.processing) _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final document = ref.watch(documentProvider(widget.documentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(document.valueOrNull?.title ?? ''),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'enhance' => _enhanceAll(document.valueOrNull),
              'pdf' => _exportPdf(document.valueOrNull),
              'txt' => _exportText(document.valueOrNull),
              'ocr' => _runOcr(document.valueOrNull),
              _ => null,
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                  value: 'enhance', child: Text(l10n.enhance)),
              PopupMenuItem<String>(value: 'ocr', child: Text(l10n.runOcr)),
              PopupMenuItem<String>(value: 'pdf', child: Text(l10n.exportPdf)),
              PopupMenuItem<String>(value: 'txt', child: Text(l10n.exportText)),
            ],
          ),
        ],
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (doc) {
          if (doc == null) return const SizedBox.shrink();
          // Finish any page that was captured but not yet restored.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _restorePending(doc),
          );
          return Column(
            children: <Widget>[
              if (_busy || _restoring) const LinearProgressIndicator(),
              if (_status != null)
                Padding(
                    padding: const EdgeInsets.all(12), child: Text(_status!)),
              Expanded(
                child: ListView.builder(
                  itemCount: doc.pages.length,
                  itemBuilder: (context, index) {
                    final page = doc.pages[index];
                    return Semantics(
                      label:
                          l10n.pageSemanticLabel(index + 1, doc.pages.length),
                      child: Card(
                        margin: const EdgeInsets.all(12),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Image.file(
                              File(page.displayPath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  size: 64),
                            ),
                            if (page.hasText)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  page.text!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Re-runs restoration over every page, from the rectified image.
  Future<void> _enhanceAll(ScanDocument? document) async {
    if (document == null) return;
    final library = await ref.read(libraryProvider.future);
    for (final page in document.pages) {
      library.setPageProcessed(
          page.id, page.processedPath ?? page.originalPath);
    }
    ref.read(libraryRevisionProvider.notifier).state++;
    final refreshed = library.document(document.id);
    if (refreshed != null) await _restorePending(refreshed);
  }

  Future<void> _runOcr(ScanDocument? document) async {
    if (document == null) return;
    final library = await ref.read(libraryProvider.future);
    setState(() => _busy = true);
    try {
      const ocr = ByrsaOcr();
      final readiness = await ocr.readiness();
      if (!readiness.ready) {
        setState(() => _status = readiness.reason);
        return;
      }
      for (final page in document.pages) {
        final result = await ocr.recognise(imagePath: page.displayPath);
        library.setPageOcr(page.id, result.text, <PageWord>[
          for (final word in result.words)
            PageWord(
              text: word.text,
              left: word.box.left,
              top: word.box.top,
              right: word.box.right,
              bottom: word.box.bottom,
            ),
        ]);
      }
      ref.read(libraryRevisionProvider.notifier).state++;
    } on Object catch (error) {
      setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(ScanDocument? document) async {
    if (document == null) return;
    final l10n = AppLocalizations.of(context)!;
    final root = await ref.read(storageRootProvider.future);
    setState(() => _busy = true);
    try {
      final pdf = SearchablePdf(title: document.title);
      for (final page in document.pages) {
        final bytes = await File(page.displayPath).readAsBytes();
        pdf.addPage(SearchablePage(
          image: PdfImage.decode(bytes),
          // TODO: word boxes are not persisted yet, so this exports the
          // image layer only when the page was recognised in an earlier
          // session. Storing boxes alongside the text is the next step and it
          // is a schema migration, not a redesign.
          words: const <PdfWord>[],
        ));
      }
      final path = p.join(root.path, '${_safeName(document.title)}.pdf');
      await File(path).writeAsBytes(pdf.build());
      setState(() => _status = l10n.exportedTo(path));
    } on Object catch (error) {
      setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportText(ScanDocument? document) async {
    if (document == null) return;
    final l10n = AppLocalizations.of(context)!;
    final root = await ref.read(storageRootProvider.future);
    final path = p.join(root.path, '${_safeName(document.title)}.txt');
    await File(path).writeAsString(document.text);
    if (mounted) setState(() => _status = l10n.exportedTo(path));
  }

  static String _safeName(String title) => title
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
}
