// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa_ocr/byrsa_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
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
          if (mounted && total > 0) setState(() => _progress = received / total);
        },
      );
      ref.read(libraryRevisionProvider.notifier).state++;
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }
}
