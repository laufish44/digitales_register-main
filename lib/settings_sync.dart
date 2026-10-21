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

/// The same settings on every device, stored in the register itself.
///
/// The register has no place for app data, but it keeps reminders
/// ("Erinnerungen"), and the app can read and write those on every device the
/// user logs in on. So the settings travel as reminders:
///
///  * Only what differs from the defaults is sent, and only what is not
///    specific to one device (saving the password, notifications, the
///    background service, where updates come from, …).
///  * It is compressed and cut into pieces: a reminder holds at most 210
///    characters (tested against the register). Each piece is one reminder,
///    `#dr-sync <stamp> <i>/<n> <data>`.
///  * They sit on the earliest day the register still lists under "past" —
///    the first day of school as far as seen — so they are out of the way on
///    the website too. Should that window turn out to move along with the
///    date, they are written again before they fall out of it.
///  * The app never shows them; see [isSettingsSyncText].
///
/// The newest complete set wins. A device that changes a setting writes a new
/// set and removes the old ones; a device that starts reads the set and takes
/// it over if it is newer than its own last change.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/wrapper.dart';
import 'package:dr/school_year.dart';
import 'package:dr/serializers.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settingsSyncMarker = "#dr-sync";

/// The register cuts reminders off after this many characters.
const reminderMaxLength = 210;

/// Whether a reminder's text is one of the pieces of the synced settings.
bool isSettingsSyncText(String? text) =>
    text != null && text.startsWith("$settingsSyncMarker ");

/// Settings that belong to one device and therefore stay where they are.
const deviceOnlySettings = {
  "noPasswordSaving",
  "noDataSaving",
  "deleteDataOnLogout",
  "drawerFullyExpanded",
  "notificationsEnabled",
  "notificationIntervalSeconds",
  "backgroundServiceEnabled",
  "prefetchAttachments",
  "prefetchWholeCalendar",
  "updateCheckEnabled",
  "releaseSource",
  "schoolCalendarRevision",
  "scrollToSubjectNicks",
  "scrollToGrades",
};

/// The settings as a flat JSON map, keyed by field name.
Map<String, Object?> _fields(SettingsState settings) {
  final list = serializers.serializeWith(SettingsState.serializer, settings)!
      as Iterable<Object?>;
  final result = <String, Object?>{};
  final items = list.toList();
  for (var i = 0; i + 1 < items.length; i += 2) {
    result[items[i]! as String] = items[i + 1];
  }
  return result;
}

SettingsState _fromFields(Map<String, Object?> fields) {
  final list = <Object?>[
    for (final entry in fields.entries) ...[entry.key, entry.value],
  ];
  return serializers.deserializeWith(SettingsState.serializer, list)!;
}

/// What of [settings] is synced: the fields that differ from the defaults and
/// are not device-only.
Map<String, Object?> syncedPart(SettingsState settings) {
  final defaults = _fields(SettingsState());
  final current = _fields(settings);
  return {
    for (final entry in current.entries)
      if (!deviceOnlySettings.contains(entry.key) &&
          jsonEncode(entry.value) != jsonEncode(defaults[entry.key]))
        entry.key: entry.value,
  };
}

/// [local] with the synced part replaced by [remote]: fields [remote] does
/// not mention go back to their defaults, device-only fields stay.
SettingsState applySyncedPart(
  SettingsState local,
  Map<String, Object?> remote, {
  bool keepLocalExtras = false,
}) {
  final defaults = _fields(SettingsState());
  final fields = _fields(local);
  for (final key in {...defaults.keys, ...fields.keys}) {
    if (deviceOnlySettings.contains(key)) continue;
    if (remote.containsKey(key)) {
      fields[key] = remote[key];
    } else if (!keepLocalExtras) {
      if (defaults.containsKey(key)) {
        fields[key] = defaults[key];
      } else {
        fields.remove(key);
      }
    }
  }
  try {
    return _fromFields(fields);
  } catch (e) {
    // A field this version does not know (sent by a newer one): leave it out.
    log("synced settings partly unreadable", error: e);
    final known = _fields(local);
    return _fromFields({
      for (final entry in fields.entries)
        if (known.containsKey(entry.key) || defaults.containsKey(entry.key))
          entry.key: entry.value,
    });
  }
}

/// One set of synced settings, as written at [stamp] (ms since epoch).
class SyncedSettings {
  const SyncedSettings(this.stamp, this.fields);

  final int stamp;
  final Map<String, Object?> fields;
}

/// The reminder texts that carry [fields], written at [stamp].
List<String> encodeSettingsPieces(Map<String, Object?> fields, int stamp) {
  final packed = base64Url
      .encode(gzip.encode(utf8.encode(jsonEncode(fields))))
      .replaceAll("=", "");
  final id = stamp.toRadixString(36);
  // Room for "#dr-sync <id> 99/99 ".
  final room = reminderMaxLength - settingsSyncMarker.length - id.length - 9;
  final pieces = <String>[];
  for (var i = 0; i < packed.length; i += room) {
    pieces.add(packed.substring(
        i, i + room > packed.length ? packed.length : i + room));
  }
  if (pieces.isEmpty) pieces.add("");
  return [
    for (var i = 0; i < pieces.length; i++)
      "$settingsSyncMarker $id ${i + 1}/${pieces.length} ${pieces[i]}",
  ];
}

/// The newest complete set among [texts], or null.
SyncedSettings? decodeSettingsPieces(Iterable<String> texts) {
  final sets = <String, Map<int, String>>{};
  final sizes = <String, int>{};
  final piece = RegExp(r"^#dr-sync ([0-9a-z]+) (\d+)/(\d+) ?([A-Za-z0-9_-]*)$");
  for (final text in texts) {
    final match = piece.firstMatch(text.trim());
    if (match == null) continue;
    final id = match.group(1)!;
    sets.putIfAbsent(id, () => {})[int.parse(match.group(2)!)] =
        match.group(4)!;
    sizes[id] = int.parse(match.group(3)!);
  }
  final ids = sets.keys.toList()
    ..sort(
        (a, b) => int.parse(b, radix: 36).compareTo(int.parse(a, radix: 36)));
  for (final id in ids) {
    final parts = sets[id]!;
    final size = sizes[id]!;
    if (parts.length != size) continue;
    try {
      var packed = [for (var i = 1; i <= size; i++) parts[i]!].join();
      packed = packed.padRight((packed.length + 3) ~/ 4 * 4, "=");
      final decoded =
          jsonDecode(utf8.decode(gzip.decode(base64Url.decode(packed))));
      if (decoded is! Map) continue;
      return SyncedSettings(
        int.parse(id, radix: 36),
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (e) {
      log("unreadable synced settings $id", error: e);
    }
  }
  return null;
}

/// A reminder of the synced settings as found in the register.
class _Piece {
  const _Piece(this.id, this.text, this.date);

  final int id;
  final String text;
  final UtcDateTime date;
}

class SettingsSync {
  SettingsSync._();

  static final instance = SettingsSync._();

  /// The connection to the register; handed over on login.
  Wrapper? _wrapper;

  bool _applying = false;
  bool _running = false;
  Timer? _upload;
  String? _user;
  Map<String, Object?>? _lastKnown;

  String get _stampKey => "settings_sync_changed_at_${_user ?? ""}";

  /// Called after every action: notices settings changes and uploads them a
  /// little later (changes come in bursts while someone is in the settings).
  void watch(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
      SettingsState? before) {
    final settings = api.state.settingsState;
    if (identical(before, settings) || _applying) return;
    final wrapper = _wrapper;
    if (wrapper == null || wrapper.demoMode) return;
    if (!api.state.loginState.loggedIn) return;
    final part = syncedPart(settings);
    if (_lastKnown != null && jsonEncode(part) == jsonEncode(_lastKnown)) {
      return;
    }
    final wasKnown = _lastKnown != null;
    _lastKnown = part;
    // The first look after logging in is not a change by the user.
    if (!wasKnown) return;
    unawaited(_setLocalStamp(DateTime.now().millisecondsSinceEpoch));
    _upload?.cancel();
    _upload = Timer(const Duration(seconds: 20), () => _uploadNow(api));
  }

  Future<int> _localStamp() async =>
      (await SharedPreferences.getInstance()).getInt(_stampKey) ?? 0;

  Future<void> _setLocalStamp(int stamp) async =>
      (await SharedPreferences.getInstance()).setInt(_stampKey, stamp);

  /// Reads the register's past view: the sync pieces in it, and the earliest
  /// day it lists. Null when it could not be read.
  Future<(List<_Piece>, UtcDateTime?)?> _readPast() async {
    final dynamic data = await _wrapper!.send(
      "api/student/dashboard/dashboard",
      args: {"viewFuture": false},
    );
    if (data is! List) return null;
    final pieces = <_Piece>[];
    UtcDateTime? earliest;
    for (final dynamic rawDay in data) {
      final day = rawDay is Map ? rawDay : null;
      final date = UtcDateTime.tryParse(getString(day?["date"]) ?? "");
      if (date == null) continue;
      if (earliest == null || date.isBefore(earliest)) earliest = date;
      for (final dynamic rawItem
          in getList(day?["items"]) ?? const <dynamic>[]) {
        final item = rawItem is Map ? rawItem : null;
        final text = getString(item?["subtitle"]);
        final id = getInt(item?["id"]);
        if (id != null && isSettingsSyncText(text)) {
          pieces.add(_Piece(id, text!, date));
        }
      }
    }
    return (pieces, earliest);
  }

  /// After logging in: take over newer settings from the register, or put
  /// this device's there if they are newer.
  Future<void> syncAfterLogin(
      MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
      Wrapper wrapper) async {
    _wrapper = wrapper;
    if (_running || wrapper.demoMode) return;
    _running = true;
    try {
      _user = api.state.loginState.username;
      final past = await _readPast();
      if (past == null) return;
      final (pieces, earliest) = past;
      final remote = decodeSettingsPieces(pieces.map((p) => p.text));
      final localStamp = await _localStamp();
      final local = syncedPart(api.state.settingsState);
      _lastKnown = local;

      if (remote != null && remote.stamp > localStamp) {
        if (jsonEncode(remote.fields) != jsonEncode(local)) {
          // Never touched on this device since syncing exists: keep what it
          // has on top, the register's set wins where both say something.
          final merge = localStamp == 0 && local.isNotEmpty;
          final settings = applySyncedPart(
            api.state.settingsState,
            remote.fields,
            keepLocalExtras: merge,
          );
          _applying = true;
          try {
            await api.actions.mountAppState(
              api.state.rebuild((b) => b..settingsState.replace(settings)),
            );
          } finally {
            _applying = false;
          }
          _lastKnown = syncedPart(api.state.settingsState);
          if (merge && jsonEncode(_lastKnown) != jsonEncode(remote.fields)) {
            await _setLocalStamp(DateTime.now().millisecondsSinceEpoch);
            await _write(pieces, earliest);
            return;
          }
        }
        await _setLocalStamp(remote.stamp);
        await _keepInWindow(pieces, earliest, remote);
        return;
      }

      final needsUpload = remote == null
          ? local.isNotEmpty || localStamp > 0
          : remote.stamp < localStamp;
      if (needsUpload) {
        if (localStamp == 0) {
          await _setLocalStamp(DateTime.now().millisecondsSinceEpoch);
        }
        await _write(pieces, earliest);
      } else if (remote != null) {
        await _keepInWindow(pieces, earliest, remote);
      }
    } catch (e, trace) {
      log("settings sync failed", error: e, stackTrace: trace);
    } finally {
      _running = false;
    }
  }

  /// Writes the set again when the past view turns out to be a moving window
  /// and the pieces are about to leave it.
  Future<void> _keepInWindow(
      List<_Piece> pieces, UtcDateTime? earliest, SyncedSettings remote) async {
    if (earliest == null || pieces.isEmpty) return;
    final rolling = earliest.isAfter(firstSchoolDay(now));
    final oldest =
        pieces.map((p) => p.date).reduce((a, b) => a.isBefore(b) ? a : b);
    if (rolling && oldest.isBefore(earliest.add(const Duration(days: 14)))) {
      log("settings sync: past view is a moving window, writing again");
      await _write(pieces, earliest,
          fields: remote.fields, stamp: remote.stamp);
    }
  }

  Future<void> _uploadNow(
      MiddlewareApi<AppState, AppStateBuilder, AppActions> api) async {
    if (_running || !api.state.loginState.loggedIn) return;
    _running = true;
    try {
      final past = await _readPast();
      if (past == null) return;
      await _write(past.$1, past.$2);
    } catch (e, trace) {
      log("settings upload failed", error: e, stackTrace: trace);
    } finally {
      _running = false;
    }
  }

  /// Writes the current set and then removes [old]. On any failure the new
  /// pieces are removed again and the old set stays.
  Future<void> _write(
    List<_Piece> old,
    UtcDateTime? earliest, {
    Map<String, Object?>? fields,
    int? stamp,
  }) async {
    final part = fields ?? _lastKnown ?? const {};
    final at = stamp ?? await _localStamp();
    final today = UtcDateTime(now.year, now.month, now.day);
    // The earliest day the register lists; if that is a moving window, today
    // keeps them in it the longest.
    final rolling = earliest != null && earliest.isAfter(firstSchoolDay(now));
    final date = earliest == null || rolling ? today : earliest;
    final written = <int>[];
    for (final text in encodeSettingsPieces(part, at)) {
      final dynamic result = await _wrapper!.send(
        "api/student/dashboard/save_reminder",
        args: {"date": DateFormat("yyyy-MM-dd").format(date), "text": text},
      );
      final id = getInt(result is Map ? result["id"] : null);
      final saved = getString(result is Map ? result["subtitle"] : null);
      if (id == null || saved != text) {
        // Cut off or not saved: this set is useless.
        if (id != null) written.add(id);
        for (final w in written) {
          await _wrapper!
              .send("api/student/dashboard/delete_reminder", args: {"id": w});
        }
        log("settings sync: writing a piece failed");
        return;
      }
      written.add(id);
    }
    for (final piece in old) {
      await _wrapper!.send("api/student/dashboard/delete_reminder",
          args: {"id": piece.id});
    }
  }
}

/// Watches the settings for changes; see [SettingsSync.watch].
NextActionHandler settingsSyncMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          final before = api.state.settingsState;
          await next(action);
          SettingsSync.instance.watch(api, before);
        };
