// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa_restore/byrsa_restore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_database.dart';
import 'providers.dart';

/// The handful of choices that must survive leaving a screen.
///
/// A filter that resets to Colour every time you come back is not a
/// preference, it is a nuisance.
class Preferences {
  const Preferences({
    this.filter = PageFilter.colour,
    this.autoCapture = true,
    this.recogniseAutomatically = false,
    this.dewarp = true,
  });

  final PageFilter filter;
  final bool autoCapture;

  /// Whether to run OCR as soon as a page has been restored.
  ///
  /// Off by default, and deliberately: on Android the first run downloads
  /// models, and a scanner that reaches for the network without being asked is
  /// exactly what this project exists not to be.
  final bool recogniseAutomatically;

  /// Whether to flatten curved pages when the model is present.
  ///
  /// On by default because it costs nothing when the model has not been
  /// downloaded — the stage reports itself unavailable and the pipeline
  /// carries on.
  final bool dewarp;

  Preferences copyWith({
    PageFilter? filter,
    bool? autoCapture,
    bool? recogniseAutomatically,
    bool? dewarp,
  }) =>
      Preferences(
        filter: filter ?? this.filter,
        autoCapture: autoCapture ?? this.autoCapture,
        recogniseAutomatically:
            recogniseAutomatically ?? this.recogniseAutomatically,
        dewarp: dewarp ?? this.dewarp,
      );
}

class PreferencesNotifier extends StateNotifier<Preferences> {
  PreferencesNotifier(this._database) : super(_read(_database));

  final LibraryDatabase? _database;

  static Preferences _read(LibraryDatabase? database) {
    if (database == null) return const Preferences();
    return Preferences(
      filter: PageFilter.values.firstWhere(
        (value) => value.name == database.setting('filter'),
        orElse: () => PageFilter.colour,
      ),
      autoCapture: database.setting('autoCapture') != 'false',
      recogniseAutomatically: database.setting('autoOcr') == 'true',
      dewarp: database.setting('dewarp') != 'false',
    );
  }

  void setFilter(PageFilter filter) {
    _database?.setSetting('filter', filter.name);
    state = state.copyWith(filter: filter);
  }

  void setAutoCapture({required bool enabled}) {
    _database?.setSetting('autoCapture', '$enabled');
    state = state.copyWith(autoCapture: enabled);
  }

  void setRecogniseAutomatically({required bool enabled}) {
    _database?.setSetting('autoOcr', '$enabled');
    state = state.copyWith(recogniseAutomatically: enabled);
  }

  void setDewarp({required bool enabled}) {
    _database?.setSetting('dewarp', '$enabled');
    state = state.copyWith(dewarp: enabled);
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesNotifier, Preferences>((ref) {
  // Until the database is open the defaults apply; the notifier is rebuilt
  // with the stored values as soon as it is.
  return PreferencesNotifier(ref.watch(libraryProvider).valueOrNull);
});
