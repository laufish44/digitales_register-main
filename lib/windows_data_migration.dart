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

/// Brings back the data that 8.6.0 left behind on Windows (issue #7).
///
/// On Windows the plugins keep their files in
/// `%APPDATA%\<CompanyName>\<ProductName>`, read from the version resource of
/// the .exe. 8.6.0 changed those two (to "Laurin Feichter" / "Digitales
/// Register"), so it looked in an empty folder: logged out, settings and
/// subject nicknames gone. The old files are still there and readable — the
/// encryption key lives in the credential store under a fixed name.
library;

import 'dart:developer';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where everything lived up to 8.5.0, relative to `%APPDATA%`.
const _oldFolder = r"it.digitalesregisterapp\digitales_register";

/// Written once the old data has been taken over, so it happens only once.
const _marker = "daten-aus-8.5-uebernommen";

/// Files to leave behind: the "project unmaintained" note is gone.
const _skip = {"unmaintainedAlertShown"};

/// Copies the data of the old folder into the current one, once.
///
/// The saved app state of an account (settings, nicknames, cached data) comes
/// from the old folder even if 8.6.x already wrote one — that is what was
/// lost; what it replaces is kept in a backup folder. The stored login and
/// the shared preferences only fill gaps, so a login made since then wins.
/// Never throws: at worst everything stays as it is.
Future<void> recoverDataFromOldFolder() async {
  if (!Platform.isWindows) return;
  try {
    final appData = Platform.environment["APPDATA"];
    if (appData == null) return;
    await migrateFolder(
      from: Directory("$appData\\$_oldFolder"),
      to: await getApplicationSupportDirectory(),
    );
  } catch (e, trace) {
    log("could not take over the data of 8.5", error: e, stackTrace: trace);
  }
}

/// The work of [recoverDataFromOldFolder], with the folders passed in so it
/// can be tested.
Future<void> migrateFolder({
  required Directory from,
  required Directory to,
}) async {
  if (from.absolute.path.toLowerCase() == to.absolute.path.toLowerCase()) {
    return;
  }
  final marker = File("${to.path}\\$_marker");
  if (await marker.exists() || !await from.exists()) return;
  await to.create(recursive: true);

  final backup = Directory("${to.path}\\Sicherung vor Datenübernahme");
  var copied = 0;
  await for (final entity in from.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (_skip.contains(name)) continue;
    final target = File("${to.path}\\$name");
    final onlyIfMissing =
        name == "shared_preferences.json" || name.endsWith("_login.secure");
    if (await target.exists()) {
      if (onlyIfMissing) continue;
      await backup.create(recursive: true);
      await target.copy("${backup.path}\\$name");
    }
    await entity.copy(target.path);
    copied++;
  }
  await marker.writeAsString(
    "Übernommen aus ${from.path} am ${DateTime.now().toIso8601String()} "
    "($copied Dateien)",
  );
  log("took over $copied files of the 8.5 data folder");
}
