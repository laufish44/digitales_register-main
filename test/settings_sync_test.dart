// Copyright (C) 2026 Laurin Feichter
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final customised = SettingsState().rebuild(
    (b) => b
      ..askWhenDelete = !SettingsState().askWhenDelete
      ..absenceWarningThreshold = 15
      ..subjectNicks = MapBuilder({
        for (var i = 0; i < 40; i++) "Fach Nummer $i mit langem Namen": "F$i",
      })
      // Device-only: must not travel.
      ..notificationsEnabled = !SettingsState().notificationsEnabled,
  );

  test("only what differs and is not device-only is synced", () {
    final part = syncedPart(customised);
    expect(
        part.keys,
        containsAll(
            ["askWhenDelete", "absenceWarningThreshold", "subjectNicks"]));
    expect(part.containsKey("notificationsEnabled"), isFalse);
    expect(syncedPart(SettingsState()), isEmpty);
  });

  test("pieces fit into a reminder and come back whole", () {
    final part = syncedPart(customised);
    final pieces = encodeSettingsPieces(part, 1761040000000);
    expect(pieces.length, greaterThan(1));
    for (final piece in pieces) {
      expect(piece.length, lessThanOrEqualTo(reminderMaxLength));
      expect(isSettingsSyncText(piece), isTrue);
    }
    final back = decodeSettingsPieces(pieces.reversed)!;
    expect(back.stamp, 1761040000000);
    expect(back.fields, part);
  });

  test("the newest complete set wins, an incomplete one is ignored", () {
    final older = encodeSettingsPieces({"askWhenDelete": false}, 1000);
    final newer = encodeSettingsPieces({"askWhenDelete": true}, 2000);
    final newest = encodeSettingsPieces(syncedPart(customised), 3000);
    final found = decodeSettingsPieces([
      ...older,
      ...newer,
      ...newest.skip(1), // a piece missing
    ])!;
    expect(found.stamp, 2000);
  });

  test("applying a set keeps device-only settings and resets the rest", () {
    final local = SettingsState().rebuild(
      (b) => b
        ..weeklyLessons = 30
        ..notificationsEnabled = !SettingsState().notificationsEnabled,
    );
    final applied = applySyncedPart(local, syncedPart(customised));
    expect(applied.askWhenDelete, customised.askWhenDelete);
    expect(applied.subjectNicks.length, 40);
    // Not in the set: back to the default.
    expect(applied.weeklyLessons, SettingsState().weeklyLessons);
    // Device-only: stays as it was here.
    expect(applied.notificationsEnabled, local.notificationsEnabled);

    final merged =
        applySyncedPart(local, syncedPart(customised), keepLocalExtras: true);
    expect(merged.weeklyLessons, 30);
  });

  test("other text is not taken for a piece", () {
    expect(isSettingsSyncText("Kapitel 3 lernen"), isFalse);
    expect(isSettingsSyncText(null), isFalse);
    expect(decodeSettingsPieces(["#dr-sync kaputt"]), isNull);
  });
}
