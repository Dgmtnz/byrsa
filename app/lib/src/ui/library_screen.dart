// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/capture'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: Text(l10n.scan),
      ),
    );
  }
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
              ),
            for (final document in docs) _DocumentTile(document: document),
          ],
        );
      },
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.document});

  final ScanDocument document;

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
      onTap: () => context.push('/document/${document.id}'),
    );
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
