// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:byrsa_capture/byrsa_capture.dart';
import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:dart_searchable_pdf/dart_searchable_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'corner_editor_screen.dart';

import '../../l10n/app_localizations.dart';
import '../data/image_io.dart';
import '../data/library_database.dart';
import '../data/preferences.dart';
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
      final preferences = ref.read(preferencesProvider);
      final store = await ref.read(modelStoreProvider.future);
      final io = ImageIo(
        filter: preferences.filter,
        dewarpModelPath: preferences.dewarp && store.isInstalled('uvdoc-grid')
            ? store.fileFor('uvdoc-grid').path
            : null,
      );
      for (final page in pending) {
        final outcome = await io.restoreFile(
          // Always from the perspective-corrected page, never from a previous
          // restoration: applying the correction twice compounds it.
          inputPath: page.processedPath ?? page.originalPath,
          outputPath: '${page.originalPath}.restored.jpg',
        );
        await _forgetCached(outcome.path);
        library.setPageRestored(page.id, outcome.path);
        if (mounted) ref.read(libraryRevisionProvider.notifier).state++;

        // Recognition follows enhancement when the user has asked for it, and
        // only then: on Android the first run downloads models, and reaching
        // for the network unasked is what this project exists not to do.
        if (ref.read(preferencesProvider).recogniseAutomatically) {
          await _recognisePage(library, page.id, outcome.path);
        }
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
              'pdf' => _exportPdf(document.valueOrNull),
              'txt' => _exportText(document.valueOrNull),
              'ocr' => _runOcr(document.valueOrNull),
              'filter-colour' =>
                _setFilter(PageFilter.colour, document.valueOrNull),
              'filter-grayscale' =>
                _setFilter(PageFilter.grayscale, document.valueOrNull),
              'filter-bw' =>
                _setFilter(PageFilter.blackAndWhite, document.valueOrNull),
              _ => null,
            },
            itemBuilder: (context) {
              final filter = ref.watch(preferencesProvider).filter;
              return <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'ocr', child: Text(l10n.runOcr)),
                PopupMenuItem<String>(
                    value: 'pdf', child: Text(l10n.exportPdf)),
                PopupMenuItem<String>(
                    value: 'txt', child: Text(l10n.exportText)),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    l10n.filter,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'filter-colour',
                  checked: filter == PageFilter.colour,
                  child: Text(l10n.filterColour),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'filter-grayscale',
                  checked: filter == PageFilter.grayscale,
                  child: Text(l10n.filterGrayscale),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'filter-bw',
                  checked: filter == PageFilter.blackAndWhite,
                  child: Text(l10n.filterBlackAndWhite),
                ),
              ];
            },
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
                    return _PageCard(
                      page: page,
                      position: index,
                      total: doc.pages.length,
                      onAdjustCorners: () => _adjustCorners(page),
                      onDelete: () => _deletePage(page),
                      onMoveLeft: () => _movePage(doc, index, index - 1),
                      onMoveRight: () => _movePage(doc, index, index + 1),
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

  /// Switches the look of every page, which means restoring them again.
  Future<void> _setFilter(PageFilter filter, ScanDocument? document) async {
    ref.read(preferencesProvider.notifier).setFilter(filter);
    if (document == null) return;
    final library = await ref.read(libraryProvider.future);
    for (final page in document.pages) {
      // Back to the rectified image: restoring a restored page would apply
      // the correction twice.
      library.setPageProcessed(
          page.id, page.processedPath ?? page.originalPath);
    }
    ref.read(libraryRevisionProvider.notifier).state++;
    final refreshed = library.document(document.id);
    if (refreshed != null) await _restorePending(refreshed);
  }

  /// Re-warps a page from corners the user dragged, on the original frame.
  ///
  /// Detection fails on low-contrast paper and cluttered desks, and retaking
  /// the photograph usually fails the same way for the same reason. This is the
  /// recovery, and it is why the original frame is never thrown away.
  Future<void> _adjustCorners(ScanPage page) async {
    final stored = page.quad;
    final quad = await Navigator.of(context).push<CaptureQuad>(
      MaterialPageRoute<CaptureQuad>(
        builder: (_) => CornerEditorScreen(
          imagePath: page.originalPath,
          initialQuad: stored == null
              ? CaptureQuad.full
              : CaptureQuad.fromPoints(<CapturePoint>[
                  for (var i = 0; i < 4; i++)
                    CapturePoint(stored[i * 2], stored[i * 2 + 1]),
                ]),
        ),
      ),
    );
    if (quad == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final rectified = await ByrsaCapturePlatform.instance.rectify(
        imagePath: page.originalPath,
        quad: quad,
        targetAspectRatio: quad.aspectRatioOrFallback(),
      );
      await _forgetCached(rectified);
      final library = await ref.read(libraryProvider.future);
      library.setPageProcessed(
        page.id,
        rectified,
        quad: <double>[
          for (final corner in quad.corners) ...<double>[corner.x, corner.y],
        ],
      );
      ref.read(libraryRevisionProvider.notifier).state++;
    } on Object catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePage(ScanPage page) async {
    final library = await ref.read(libraryProvider.future);
    library.deletePage(page.id);
    ref.read(libraryRevisionProvider.notifier).state++;
  }

  Future<void> _movePage(ScanDocument document, int from, int to) async {
    if (to < 0 || to >= document.pages.length) return;
    final order = document.pages.map((page) => page.id).toList();
    order.insert(to, order.removeAt(from));
    final library = await ref.read(libraryProvider.future);
    library.reorderPages(document.id, order);
    ref.read(libraryRevisionProvider.notifier).state++;
  }

  /// Forgets a cached decode of [path].
  ///
  /// Flutter caches decoded images by path and size, so rewriting a file in
  /// place leaves the old picture on screen. Restoring with a different filter,
  /// or re-warping after correcting corners, does exactly that — and the
  /// symptom is an action that appears to do nothing at all.
  static Future<void> _forgetCached(String path) async {
    final image = FileImage(File(path));
    await image.evict();
  }

  /// Recognises one page and stores the text with its word boxes.
  ///
  /// Returns quietly when no engine is ready: an automatic step must never
  /// interrupt with an error the user did not ask to see.
  Future<void> _recognisePage(
    LibraryDatabase library,
    int pageId,
    String imagePath,
  ) async {
    try {
      const ocr = ByrsaOcr();
      if (!(await ocr.readiness()).ready) return;
      final result = await ocr.recognise(imagePath: imagePath);
      library.setPageOcr(pageId, result.text, <PageWord>[
        for (final word in result.words)
          PageWord(
            text: word.text,
            left: word.box.left,
            top: word.box.top,
            right: word.box.right,
            bottom: word.box.bottom,
          ),
      ]);
      if (mounted) ref.read(libraryRevisionProvider.notifier).state++;
    } on Object {
      // Recognition is an enhancement, not the point. A failure costs the
      // text, never the scan.
    }
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
        await _recognisePage(library, page.id, page.displayPath);
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
          // The boxes are in the coordinate space of the image being embedded:
          // recognition runs on the restored page, and `displayPath` returns
          // that same file once restoration has written it.
          words: <PdfWord>[
            for (final word in page.words)
              PdfWord(
                word.text,
                PdfRect(word.left, word.top, word.right, word.bottom),
              ),
          ],
        ));
      }
      final path = p.join(root.path, '${_safeName(document.title)}.pdf');
      await File(path).writeAsBytes(pdf.build());
      if (mounted) setState(() => _status = l10n.exportedTo(path));
      await _offer(path, document.title);
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
    await _offer(path, document.title);
  }

  /// Hands the exported file to the system share sheet.
  ///
  /// Without this, export writes into a sandbox directory the user cannot
  /// reach on either platform, which makes the feature a lie. The file is also
  /// left on disk, so a file manager can find it where one exists.
  Future<void> _offer(String path, String title) async {
    await Share.shareXFiles(<XFile>[XFile(path)], subject: title);
  }

  static String _safeName(String title) => title
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
}

/// One page, with the actions that belong to a page rather than a document.
class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.page,
    required this.position,
    required this.total,
    required this.onAdjustCorners,
    required this.onDelete,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final ScanPage page;
  final int position;
  final int total;
  final VoidCallback onAdjustCorners;
  final VoidCallback onDelete;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: l10n.pageSemanticLabel(position + 1, total),
      child: Card(
        margin: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Image.file(
              File(page.displayPath),
              fit: BoxFit.contain,
              // A page that is being restored right now is briefly replaced on
              // disk, so a failed decode is a normal transient, not an error.
              errorBuilder: (_, __, ___) => const SizedBox(
                  height: 120, child: Icon(Icons.hourglass_empty)),
            ),
            if (page.hasText)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  page.text!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  tooltip: l10n.movePageLeft,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: position == 0 ? null : onMoveLeft,
                ),
                IconButton(
                  tooltip: l10n.movePageRight,
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: position == total - 1 ? null : onMoveRight,
                ),
                IconButton(
                  tooltip: l10n.adjustCorners,
                  icon: const Icon(Icons.crop_free),
                  onPressed: onAdjustCorners,
                ),
                IconButton(
                  tooltip: l10n.deletePage,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
