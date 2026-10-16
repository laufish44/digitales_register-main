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

@TestOn("windows")
library;

import 'dart:io';

import 'package:dr/windows_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root, from, to;
  const state = "dr_{_username___max_,_server_url___x_}.secure";
  const login = "dr_login.secure";

  setUp(() async {
    root = await Directory.systemTemp.createTemp("dr_migration");
    from = Directory("${root.path}\\old")..createSync();
    to = Directory("${root.path}\\new");
    File("${from.path}\\$state").writeAsStringSync("alter Zustand");
    File("${from.path}\\$login").writeAsStringSync("alter Login");
    File("${from.path}\\shared_preferences.json").writeAsStringSync("alt");
    File("${from.path}\\unmaintainedAlertShown").writeAsStringSync("");
  });

  tearDown(() => root.delete(recursive: true));

  String read(String name) => File("${to.path}\\$name").readAsStringSync();

  test("an empty new folder gets everything back", () async {
    await migrateFolder(from: from, to: to);
    expect(read(state), "alter Zustand");
    expect(read(login), "alter Login");
    expect(read("shared_preferences.json"), "alt");
    expect(File("${to.path}\\unmaintainedAlertShown").existsSync(), isFalse);
  });

  // Someone who logged in again on 8.6.x: their new login stays, the old
  // settings come back, and what they replace is kept.
  test("keeps a newer login but restores the saved state", () async {
    to.createSync();
    File("${to.path}\\$state").writeAsStringSync("neuer Zustand");
    File("${to.path}\\$login").writeAsStringSync("neuer Login");
    await migrateFolder(from: from, to: to);
    expect(read(state), "alter Zustand");
    expect(read(login), "neuer Login");
    expect(
      File("${to.path}\\Sicherung vor Datenübernahme\\$state")
          .readAsStringSync(),
      "neuer Zustand",
    );
  });

  test("happens only once", () async {
    await migrateFolder(from: from, to: to);
    File("${to.path}\\$state").writeAsStringSync("später geändert");
    await migrateFolder(from: from, to: to);
    expect(read(state), "später geändert");
  });

  test("does nothing without an old folder", () async {
    await from.delete(recursive: true);
    await migrateFolder(from: from, to: to);
    expect(to.existsSync(), isFalse);
  });
}
