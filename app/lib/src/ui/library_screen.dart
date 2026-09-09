// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../data/providers.dart';
import '../domain/document.dart';

/// The library: folders, documents, and search across everything in them.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.folderId});

  final int? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: l10n.newFolder,
            onPressed: () => _createFolder(context, ref, folderId),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SearchBar(
              hintText: l10n.searchHint,
              leading: const Icon(Icons.search),
              onChanged: (value) =>
                  ref.read(searchQueryProvider.notifier).state = value,
            ),
          ),
        ),
      ),
      body: query.trim().isEmpty
          ? _Browser(folderId: folderId)
          : const _SearchResults(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          // Importing an existing photograph matters more than it looks:
          // plenty of documents arrive as a picture somebody else took.
          FloatingActionButton.small(
            heroTag: 'import',
            tooltip: l10n.importImage,
            onPressed: () => _importImage(context, ref, folderId),
            child: const Icon(Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: () => context.push('/capture'),
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(l10n.scan),
          ),
        ],
      ),
    );
  }
}

/// Brings a photograph the user already has into the library.
///
/// It goes in as the original frame with no quad, so it takes the same path as
/// a capture: the corners can be set by hand and restoration runs over it.
Future<void> _importImage(
    BuildContext context, WidgetRef ref, int? folderId) async {
  final images = await ImagePicker().pickMultiImage();
  if (images.isEmpty) return;

  final library = await ref.read(libraryProvider.future);
  final title =
      'Importado ${DateTime.now().toIso8601String().substring(0, 16)}';
  final documentId = library.createDocument(title, folderId: folderId);
  for (final image in images) {
    library.addPage(documentId, originalPath: image.path);
  }
  ref.read(libraryRevisionProvider.notifier).state++;
  if (context.mounted) context.push('/document/$documentId');
}

/// Asks for a name and creates a folder in the current one.
Future<void> _createFolder(
    BuildContext context, WidgetRef ref, int? parentId) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.newFolder),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.folderName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  if (name == null || name.trim().isEmpty) return;

  final library = await ref.read(libraryProvider.future);
  library.createFolder(name.trim(), parentId: parentId);
  ref.read(libraryRevisionProvider.notifier).state++;
}

class _Browser extends ConsumerWidget {
  const _Browser({this.folderId});

  final int? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final folders = ref.watch(foldersProvider(folderId));
    final documents = ref.watch(documentsProvider(folderId));

    return documents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (docs) {
        final subfolders = folders.valueOrNull ?? const <Folder>[];
        if (docs.isEmpty && subfolders.isEmpty) {
          return Center(child: Text(l10n.noDocuments));
        }
        return ListView(
          children: <Widget>[
            for (final folder in subfolders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () => context.push('/folder/${folder.id}'),
                onLongPress: () async {
                  // Deleting a folder leaves the documents in it alone; they
                  // fall back to the root. Losing a folder is an accident,
                  // losing the scans inside it is a disaster.
                  final library = await ref.read(libraryProvider.future);
                  library.deleteFolder(folder.id);
                  ref.read(libraryRevisionProvider.notifier).state++;
                },
              ),
            for (final document in docs)
              _DocumentTile(
                document: document,
                onRename: (title) async {
                  final library = await ref.read(libraryProvider.future);
                  library.renameDocument(document.id, title);
                  ref.read(libraryRevisionProvider.notifier).state++;
                },
                onDelete: () async {
                  final library = await ref.read(libraryProvider.future);
                  final storage = await ref.read(scanStorageProvider.future);
                  library.deleteDocument(document.id);
                  // The images go too. Otherwise the only symptom is a phone
                  // that slowly fills up with documents the user deleted.
                  await storage.discard(document.id);
                  ref.read(libraryRevisionProvider.notifier).state++;
                },
              ),
          ],
        );
      },
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onRename,
    required this.onDelete,
  });

  final ScanDocument document;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final first = document.pages.isEmpty ? null : document.pages.first;

    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 56,
        child: first == null
            ? const Icon(Icons.description_outlined)
            : Image.file(File(first.displayPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined)),
      ),
      title: Text(document.title),
      subtitle: Text(
        '${l10n.pageCount(document.pageCount)} · '
        '${document.isSearchable ? l10n.searchable : l10n.notSearchable}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'delete') {
            if (await _confirmDelete(context)) onDelete();
          } else {
            final title = await _askTitle(context, document.title);
            if (title != null) onRename(title);
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'rename', child: Text(l10n.rename)),
          PopupMenuItem<String>(value: 'delete', child: Text(l10n.delete)),
        ],
      ),
      onTap: () => context.push('/document/${document.id}'),
    );
  }

  static Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(l10n.deleteDocumentConfirm),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<String?> _askTitle(BuildContext context, String current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: current);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    return (title == null || title.trim().isEmpty) ? null : title.trim();
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ref.watch(searchResultsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (hits) => hits.isEmpty
              ? Center(child: Text(l10n.noResults))
              : ListView.builder(
                  itemCount: hits.length,
                  itemBuilder: (context, index) {
                    final hit = hits[index];
                    return ListTile(
                      title: Text(hit.title),
                      subtitle: Text(hit.snippet),
                      onTap: () => context.push('/document/${hit.documentId}'),
                    );
                  },
                ),
        );
  }
}
