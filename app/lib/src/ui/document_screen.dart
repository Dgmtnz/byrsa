// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
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
              'pdf' => _exportPdf(document.valueOrNull),
              'txt' => _exportText(document.valueOrNull),
              'ocr' => _runOcr(document.valueOrNull),
              _ => null,
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
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
          return Column(
            children: <Widget>[
              if (_busy) const LinearProgressIndicator(),
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
