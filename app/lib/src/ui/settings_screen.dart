// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../data/preferences.dart';
import '../data/providers.dart';

/// Settings, and the place where the application states its one network
/// behaviour in plain words before it ever uses it.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double? _progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readiness = ref.watch(ocrReadinessProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.privacyHeading,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(l10n.privacyBody),
                  ],
                ),
              ),
            ),
          ),
          SwitchListTile(
            title: Text(l10n.autoCapture),
            subtitle: Text(l10n.autoCaptureBody),
            value: ref.watch(preferencesProvider).autoCapture,
            onChanged: (value) => ref
                .read(preferencesProvider.notifier)
                .setAutoCapture(enabled: value),
          ),
          SwitchListTile(
            title: Text(l10n.autoOcr),
            subtitle: Text(l10n.autoOcrBody),
            value: ref.watch(preferencesProvider).recogniseAutomatically,
            onChanged: (value) => ref
                .read(preferencesProvider.notifier)
                .setRecogniseAutomatically(enabled: value),
          ),
          const Divider(),
          SwitchListTile(
            title: Text(l10n.removeIntrusions),
            subtitle: Text(l10n.removeIntrusionsBody),
            value: ref.watch(preferencesProvider).removeIntrusions,
            onChanged: (value) => ref
                .read(preferencesProvider.notifier)
                .setRemoveIntrusions(enabled: value),
          ),
          const _DewarpModelTile(),
          const Divider(),
          readiness.when(
            loading: () => const ListTile(title: LinearProgressIndicator()),
            error: (error, _) => ListTile(title: Text('$error')),
            data: (state) => ListTile(
              title: Text(l10n.ocrEngine),
              subtitle: Text(
                state.ready
                    ? state.engine
                    : l10n.downloadModelsExplanation(
                        (state.missingBytes / 1024 / 1024).round()),
              ),
              trailing: state.ready
                  ? const Icon(Icons.check_circle_outline)
                  : FilledButton(
                      onPressed: _progress != null ? null : _download,
                      child: Text(l10n.download),
                    ),
            ),
          ),
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: _progress),
            ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    setState(() => _progress = 0);
    try {
      await const ByrsaOcr().prepare(
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      ref.read(libraryRevisionProvider.notifier).state++;
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }
}

/// Downloading, and removing, the page-flattening model.
///
/// Everything the user is told here — the size, the licence — comes from
/// `models.json`, the same file a reviewer reads. A copy in the interface would
/// drift from it, and the number that drifts is always the one about how much
/// of someone's data allowance this costs.
class _DewarpModelTile extends ConsumerStatefulWidget {
  const _DewarpModelTile();

  @override
  ConsumerState<_DewarpModelTile> createState() => _DewarpModelTileState();
}

class _DewarpModelTileState extends ConsumerState<_DewarpModelTile> {
  double? _progress;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final store = ref.watch(modelStoreProvider).valueOrNull;
    final revision = ref.watch(libraryRevisionProvider);
    if (store == null) return const SizedBox.shrink();

    final model = store.catalog['uvdoc-grid'];
    final installed = store.isInstalled('uvdoc-grid');

    return Column(
      children: <Widget>[
        SwitchListTile(
          title: Text(l10n.dewarp),
          subtitle: Text(
            installed
                ? l10n.dewarpReady
                : l10n.dewarpBody(
                    (model.sizeBytes / 1024 / 1024).round(),
                    model.license,
                  ),
          ),
          value: ref.watch(preferencesProvider).dewarp,
          onChanged: (value) =>
              ref.read(preferencesProvider.notifier).setDewarp(enabled: value),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(value: _progress),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: installed
                  ? TextButton(
                      onPressed: () => _remove(store),
                      child: Text(l10n.remove),
                    )
                  : FilledButton(
                      key: ValueKey<int>(revision),
                      onPressed: () => _download(store),
                      child: Text(l10n.download),
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _download(ModelStore store) async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await store.install(
        'uvdoc-grid',
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      ref.read(libraryRevisionProvider.notifier).state++;
    } on ModelStoreException catch (error) {
      // The store's messages already say what went wrong and what to do.
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _remove(ModelStore store) async {
    await store.remove('uvdoc-grid');
    ref.read(libraryRevisionProvider.notifier).state++;
  }
}
