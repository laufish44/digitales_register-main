// Copyright (C) 2021 Michael Debertol
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

/// Reading back the login the app stored, for the background checks.
///
/// Both background workers — the Windows service and the Android alarm isolate
/// — run without the redux store, so they read the credentials straight out of
/// the secure storage entry that `middleware/pass.dart` writes.
library;

import 'dart:convert';
import 'dart:developer';

import 'package:dr/desktop.dart';
import 'package:dr/util.dart';

class StoredCredentials {
  StoredCredentials({
    required this.user,
    required this.pass,
    required this.url,
  });

  final String user;
  final String pass;
  final String url;
}

/// The credentials the app stored at login, or null if there are none.
Future<StoredCredentials?> readStoredCredentials() async {
  try {
    final raw = await getFlutterSecureStorage().read(key: "login");
    if (raw == null) return null;
    final decoded = getMap(json.decode(raw));
    final user = getString(decoded?["user"]);
    final pass = getString(decoded?["pass"]);
    final url = getString(decoded?["url"]);
    if (user == null || pass == null || url == null) return null;
    return StoredCredentials(user: user, pass: pass, url: url);
  } catch (e) {
    log("failed to read stored credentials", error: e);
    return null;
  }
}
