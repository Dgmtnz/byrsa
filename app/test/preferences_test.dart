// SPDX-FileCopyrightText: 2026 Diego Martínez Fernández
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:byrsa/src/data/library_database.dart';
import 'package:byrsa/src/data/preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('removing what holds the page down is off until it is turned on', () {
    // Off by default is the decision, not an accident of the constructor:
    // `Preferences.removeIntrusions` says what it erases when it misfires.
    final db = LibraryDatabase(sqlite3.openInMemory());
    addTearDown(db.dispose);

    expect(PreferencesNotifier(null).state.removeIntrusions, isFalse,
        reason: 'before the library is open');
    expect(PreferencesNotifier(db).state.removeIntrusions, isFalse,
        reason: 'with nothing stored');

    PreferencesNotifier(db).setRemoveIntrusions(enabled: true);
    expect(PreferencesNotifier(db).state.removeIntrusions, isTrue,
        reason: 'turned on, it stays on');
  });
}
