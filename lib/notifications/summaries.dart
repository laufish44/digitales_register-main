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

/// Notifications the app writes itself, from the register's raw answers:
///
///  * the evening summary of the next day ("Morgen: 6 Stunden, …"),
///  * how a new grade moves the subject's average.
///
/// The app, the Windows background service and the Android alarm all use
/// this, each with its own way of asking the register, so nothing here knows
/// about the redux store.
library;

import 'dart:developer';

import 'package:dr/data.dart';
import 'package:dr/hidden_entries.dart';
import 'package:dr/notifications/notification_service.dart';
import 'package:dr/notifications/notification_store.dart';
import 'package:dr/reducer/calendar.dart' show parseCalendarResponse;
import 'package:dr/reducer/grades.dart' show parseGradeAll;
import 'package:dr/settings_sync.dart' show isSettingsSyncText;
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

/// A fixed id, so a second summary on the same evening would replace the
/// first instead of stacking up.
const eveningSummaryNotificationId = 0x7ffffff0;

const _weekdays = [
  "Montag",
  "Dienstag",
  "Mittwoch",
  "Donnerstag",
  "Freitag",
  "Samstag",
  "Sonntag",
];

class EveningSummary {
  EveningSummary._();

  /// The summary of [day], or null when there is no school and nothing due.
  ///
  /// [dashboard] is the answer of `api/student/dashboard/dashboard` with
  /// `viewFuture: true`, [calendar] that of `api/calendar/student` for the
  /// week of [day]; either may be missing.
  static ({String title, String body})? compose({
    required UtcDateTime day,
    required List<dynamic>? dashboard,
    required Map<String, dynamic>? calendar,
    Map<String, String> nicks = const {},
  }) {
    String nick(String subject) {
      for (final entry in nicks.entries) {
        if (entry.key.toLowerCase() == subject.toLowerCase()) {
          return entry.value;
        }
      }
      return subject;
    }

    var lessons = 0;
    if (calendar != null) {
      try {
        final state = parseCalendarResponse(calendar);
        final calendarDay = state.days[day];
        for (final hour in calendarDay?.hours ?? const <CalendarHour>[]) {
          lessons += hour.length;
        }
      } catch (e) {
        log("evening summary: calendar not readable", error: e);
      }
    }

    final tests = <String>[];
    final homework = <String>[];
    var reminders = 0;
    // Entries hidden for oneself are left out (hidden_entries.dart).
    final hidden = hiddenKeysInRaw(dashboard);
    for (final dynamic rawDay in dashboard ?? const <dynamic>[]) {
      final map = rawDay is Map ? rawDay : null;
      if (map == null || getString(map["date"]) != _isoDay(day)) continue;
      for (final dynamic rawItem
          in getList(map["items"]) ?? const <dynamic>[]) {
        if (rawItem is! Map) continue;
        final type = getString(rawItem["type"]);
        if (hidden.contains("$type:${getInt(rawItem["id"])}")) continue;
        if (isHideMarkerText(getString(rawItem["subtitle"]))) continue;
        final subject = nick(getString(rawItem["label"]) ?? "");
        if (type == "gradeGroup") {
          if (rawItem["homework"] == 0) {
            tests.add(
                "${getString(rawItem["title"]) ?? "Test"} in $subject".trim());
          } else {
            homework.add(subject);
          }
        } else if (type == "lessonHomework") {
          homework.add(subject);
        } else if (type == "homework") {
          final text = getString(rawItem["subtitle"]) ?? "";
          if (!isSettingsSyncText(text)) reminders++;
        }
      }
    }

    if (lessons == 0 && tests.isEmpty && homework.isEmpty && reminders == 0) {
      return null;
    }
    final parts = [
      if (lessons > 0) lessons == 1 ? "1 Stunde" : "$lessons Stunden",
      ...tests,
      if (homework.isNotEmpty)
        "Hausaufgabe in ${homework.where((s) => s.isNotEmpty).toSet().join(", ")}",
      if (reminders > 0)
        reminders == 1 ? "1 Erinnerung" : "$reminders Erinnerungen",
    ];
    return (
      title: "Morgen, ${_weekdays[day.weekday - 1]} ${day.day}.${day.month}.",
      body: parts.join(" · "),
    );
  }

  /// Posts the summary of tomorrow when it is time and it was not posted
  /// today yet. Never throws.
  ///
  /// The loaders ask the register; they are only called when it is due.
  static Future<void> runIfDue({
    required DateTime now,
    required Future<List<dynamic>?> Function() loadDashboard,
    required Future<Map<String, dynamic>?> Function(UtcDateTime monday)
        loadCalendar,
  }) async {
    try {
      if (!await NotificationStore.enabled) return;
      if (!await NotificationStore.eveningSummaryEnabled) return;
      final today = "${now.year}-${now.month}-${now.day}";
      if (await NotificationStore.eveningSummaryLastDay == today) return;
      if (now.hour * 60 + now.minute <
          await NotificationStore.eveningSummaryMinutes) {
        return;
      }

      final tomorrow = UtcDateTime(now.year, now.month, now.day + 1);
      final dashboard = await loadDashboard();
      final calendar = await loadCalendar(toMonday(tomorrow));
      if (dashboard == null && calendar == null) return; // Try again later.

      await NotificationStore.setEveningSummaryLastDay(today);
      final summary = compose(
        day: tomorrow,
        dashboard: dashboard,
        calendar: calendar,
        nicks: await NotificationStore.subjectNicks,
      );
      if (summary == null) return;
      await LocalNotificationService.show(
        id: eveningSummaryNotificationId,
        title: summary.title,
        body: summary.body,
      );
    } catch (e, trace) {
      log("evening summary failed", error: e, stackTrace: trace);
    }
  }
}

String _isoDay(UtcDateTime d) =>
    "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

/// How the newest grade of a subject moved its average (#18 of the 9.0
/// list): [before] without it, [after] with it, both scaled by 100.
typedef AverageChange = ({String subject, double? before, double after});

/// From the answer of `api/student/all_subjects`. The register does not say
/// which grade a notification is about beyond the subject, so the newest one
/// entered (`createdTimeStamp`) is taken as the new one.
AverageChange? averageChange(Map<dynamic, dynamic> allSubjects, int subjectId) {
  for (final dynamic raw
      in getList(allSubjects["subjects"]) ?? const <dynamic>[]) {
    if (raw is! Map) continue;
    final subject = getMap(raw["subject"]);
    if (subject == null || getInt(subject["id"]) != subjectId) continue;
    final grades = [
      for (final dynamic g in getList(raw["grades"]) ?? const <dynamic>[])
        if (g is Map) g,
    ]..sort((a, b) => (getString(a["createdTimeStamp"]) ?? "")
        .compareTo(getString(b["createdTimeStamp"]) ?? ""));
    if (grades.isEmpty) return null;
    GradeAll? parse(Map g) {
      try {
        return parseGradeAll(g);
      } catch (_) {
        return null;
      }
    }

    final all = grades.map(parse).whereType<GradeAll>().toList();
    final after = GradeStats.subjectAverage(all);
    if (after == null) return null;
    final before = GradeStats.subjectAverage(
        grades.sublist(0, grades.length - 1).map(parse).whereType<GradeAll>());
    return (
      subject: getString(subject["name"]) ?? "",
      before: before,
      after: after,
    );
  }
  return null;
}

/// "Schnitt 7,25 → 7,38", or "Schnitt 7,38" for the first grade.
String formatAverageChange(AverageChange change) {
  String f(double v) => (v / 100).toStringAsFixed(2).replaceAll(".", ",");
  final before = change.before;
  return before == null
      ? "Schnitt ${f(change.after)}"
      : "Schnitt ${f(before)} → ${f(change.after)}";
}
