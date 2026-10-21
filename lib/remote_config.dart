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

/// What can change without a new version of the app.
///
/// `remote/config.json` in the repository is read on every start. It holds
/// data that used to need a release: the school calendar of the coming year
/// (or a correction of this one), and short notices to everyone who uses the
/// app. Editing that file on GitHub is enough — no build, no install.
///
/// The fetched file is kept, and what is kept is used from the next start on:
/// the school calendar goes into the settings once, on start, the same way a
/// calendar built into a new version does (see `schoolCalendarRevision`).
/// Notices show right away.
///
/// Nothing here can run code or change what the app sends anywhere; a broken
/// or missing file simply leaves everything as it is.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:dr/app_state.dart';
import 'package:dr/fork_info.dart';
import 'package:dr/school_year.dart';
import 'package:dr/update/update_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Where the file lives: the raw file on the default branch.
String get remoteConfigUrl {
  final repo = Uri.parse(forkSourceUrl);
  final path = repo.pathSegments.where((s) => s.isNotEmpty).toList();
  if (repo.host != "github.com" || path.length < 2) return "";
  return "https://raw.githubusercontent.com/${path[0]}/${path[1]}/master/"
      "remote/config.json";
}

/// A message to everyone, shown once as a banner.
class RemoteNotice {
  const RemoteNotice({
    required this.id,
    required this.text,
    this.title,
    this.until,
    this.platforms,
    this.belowVersion,
    this.url,
  });

  /// Shown once per id; a new id shows again.
  final String id;
  final String? title;
  final String text;

  /// Not shown after this day.
  final UtcDateTime? until;

  /// "android", "windows", …; null for all.
  final List<String>? platforms;

  /// Only for versions older than this, e.g. "update please" notices.
  final AppVersion? belowVersion;

  /// Opened by the banner's button, if set.
  final String? url;

  bool appliesTo({
    required String platform,
    required AppVersion? version,
    required UtcDateTime today,
  }) {
    if (until != null && today.isAfter(until!)) return false;
    if (platforms != null && !platforms!.contains(platform)) return false;
    if (belowVersion != null &&
        (version == null || !belowVersion!.isNewerThan(version))) {
      return false;
    }
    return true;
  }
}

class RemoteConfig {
  const RemoteConfig({
    this.calendarRevision = 0,
    this.schoolCalendars = const {},
    this.notices = const [],
  });

  /// Raised in the file whenever its school calendars change, so stored
  /// holidays are replaced once.
  final int calendarRevision;

  /// By the year the school year starts in.
  final Map<int, SchoolCalendar> schoolCalendars;

  final List<RemoteNotice> notices;

  /// What was fetched on an earlier start; used from the start of this one.
  static RemoteConfig? current;

  static const _cacheKey = "remote_config";
  static const _seenKey = "remote_notices_seen";

  // Lenient readers: a wrong type in the file means "not there", where the
  // app's own get* helpers would throw.
  static Map<dynamic, dynamic>? _map(dynamic v) => v is Map ? v : null;
  static List<dynamic>? _list(dynamic v) => v is List ? v : null;
  static String? _string(dynamic v) => v is String ? v : null;
  static int? _int(dynamic v) => v is int ? v : null;

  static UtcDateTime? _date(dynamic value) {
    final text = _string(value);
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    return parsed == null
        ? null
        : UtcDateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Reads the file; whatever is malformed is left out rather than failing
  /// the whole thing.
  static RemoteConfig? parse(String source) {
    final Map<dynamic, dynamic>? json;
    try {
      json = _map(jsonDecode(source));
    } on FormatException {
      return null;
    }
    if (json == null) return null;

    final calendars = <int, SchoolCalendar>{};
    final rawCalendars = _map(json["schoolCalendars"]) ?? const {};
    for (final entry in rawCalendars.entries) {
      final year = int.tryParse(entry.key.toString());
      final raw = _map(entry.value);
      final first = _date(raw?["firstDay"]);
      final last = _date(raw?["lastDay"]);
      if (year == null || first == null || last == null) continue;
      final holidays = <HolidayPeriod>[];
      for (final h in _list(raw?["holidays"]) ?? const <dynamic>[]) {
        final map = _map(h);
        final name = _string(map?["name"]);
        final start = _date(map?["start"]);
        final end = _date(map?["end"]) ?? start;
        if (name == null || start == null || end == null) continue;
        holidays.add(HolidayPeriod((b) => b
          ..name = name
          ..start = start
          ..end = end));
      }
      calendars[year] =
          SchoolCalendar(firstDay: first, lastDay: last, holidays: holidays);
    }

    final notices = <RemoteNotice>[];
    for (final n in _list(json["notices"]) ?? const <dynamic>[]) {
      final map = _map(n);
      final id = _string(map?["id"]);
      final text = _string(map?["text"]);
      if (id == null || text == null || text.trim().isEmpty) continue;
      notices.add(RemoteNotice(
        id: id,
        title: _string(map?["title"]),
        text: text,
        until: _date(map?["until"]),
        platforms: _list(map?["platforms"])?.map((p) => "$p").toList(),
        belowVersion: AppVersion.tryParse(_string(map?["belowVersion"])),
        url: _string(map?["url"]),
      ));
    }

    return RemoteConfig(
      calendarRevision: _int(json["calendarRevision"]) ?? 0,
      schoolCalendars: calendars,
      notices: notices,
    );
  }

  /// Takes the file fetched last time into use. Call before the store is
  /// created, so the school calendar is in place when the state is loaded.
  static Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) current = parse(raw);
    } catch (e) {
      log("could not read the stored remote config", error: e);
    }
  }

  /// Fetches the file and keeps it for the next start. Returns it, or null
  /// when it could not be had.
  static Future<RemoteConfig?> refresh({http.Client? client}) async {
    final url = remoteConfigUrl;
    if (url.isEmpty) return null;
    final ownClient = client == null;
    final c = client ?? http.Client();
    try {
      final response =
          await c.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final config = parse(body);
      if (config == null) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
      return config;
    } catch (e) {
      log("could not fetch the remote config", error: e);
      return null;
    } finally {
      if (ownClient) c.close();
    }
  }

  /// The notices of [config] that should show now and have not been seen.
  static Future<List<RemoteNotice>> unseenNotices(
    RemoteConfig config, {
    required String platform,
    required UtcDateTime today,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenKey) ?? const [];
    final version = AppVersion.tryParse(appVersion);
    return [
      for (final notice in config.notices)
        if (!seen.contains(notice.id) &&
            notice.appliesTo(
                platform: platform, version: version, today: today))
          notice,
    ];
  }

  static Future<void> markSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_seenKey) ?? <String>[];
    if (!seen.contains(id)) {
      await prefs.setStringList(_seenKey, [...seen, id]);
    }
  }
}
