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

/// The bit of state that the app and the background checks share.
///
/// The redux store lives in the app process only and is encrypted per account,
/// so neither the Windows service nor the Android alarm isolate can read it.
/// These few values are kept in `shared_preferences` instead, which all of them
/// can read and write because they are the same application.
library;

import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

/// How often the poller checks for something new, by default.
const defaultNotificationIntervalSeconds = 60;

/// The interval bounds offered in the settings.
const minNotificationIntervalSeconds = 15;
const maxNotificationIntervalSeconds = 3600;

class NotificationStore {
  NotificationStore._();

  static const _enabledKey = "notifications_enabled";
  static const _intervalKey = "notifications_interval_seconds";
  static const _backgroundServiceKey = "notifications_background_service";
  static const _seenIdsKey = "notifications_seen_ids";

  /// Keeping more than this many ids would grow without bound; notifications
  /// that old will never show up as "unread" again anyway.
  static const _maxSeenIds = 500;

  static Future<SharedPreferences> get _prefs async {
    // The background service and the app each have their own instance; always
    // reload so that a setting changed in the app is picked up by the service.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Future<bool> get enabled async =>
      (await _prefs).getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool value) async =>
      (await _prefs).setBool(_enabledKey, value);

  static Future<int> get intervalSeconds async {
    final value =
        (await _prefs).getInt(_intervalKey) ?? defaultNotificationIntervalSeconds;
    return value.clamp(
      minNotificationIntervalSeconds,
      maxNotificationIntervalSeconds,
    );
  }

  static Future<void> setIntervalSeconds(int value) async =>
      (await _prefs).setInt(
        _intervalKey,
        value.clamp(
          minNotificationIntervalSeconds,
          maxNotificationIntervalSeconds,
        ),
      );

  static Future<bool> get backgroundServiceEnabled async =>
      (await _prefs).getBool(_backgroundServiceKey) ?? false;

  static Future<void> setBackgroundServiceEnabled(bool value) async =>
      (await _prefs).setBool(_backgroundServiceKey, value);

  /// The ids of the notifications the user has already been told about.
  ///
  /// Returns null if nothing has ever been recorded. The caller must not treat
  /// that as "everything is new" — on the very first poll we only remember what
  /// is already there instead of posting a notification for every unread entry.
  static Future<Set<String>?> seenIds() async {
    try {
      return (await _prefs).getStringList(_seenIdsKey)?.toSet();
    } catch (e) {
      log("failed to read seen notification ids", error: e);
      return <String>{};
    }
  }

  /// Records [ids] as "the user knows about these".
  ///
  /// [ids] should be the full set of currently unread ids, so that entries the
  /// server no longer reports are eventually forgotten.
  static Future<void> setSeenIds(Iterable<String> ids) async {
    try {
      final list = ids.toList();
      await (await _prefs).setStringList(
        _seenIdsKey,
        list.length > _maxSeenIds
            ? list.sublist(list.length - _maxSeenIds)
            : list,
      );
    } catch (e) {
      log("failed to store seen notification ids", error: e);
    }
  }
}
