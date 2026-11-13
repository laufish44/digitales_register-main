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

/// Entries hidden for oneself.
///
/// Some teachers enter the same test on ten different days. Each of these
/// entries can be hidden: the app then counts it as if it were not there — no
/// red mark in the calendar, not in "Demnächst", the week's progress, the
/// test density, the widgets, the search or the statistics. The day keeps a
/// small "1 ausgeblendet" to bring it back.
///
/// What is hidden is kept in the register itself, so it holds on every
/// device: as a reminder on the entry's day, `#dr-hide gradeGroup:2244 …`,
/// which the app never shows (the website does). The key is the entry's
/// type and id; a test or homework has the same id on the register page and
/// in the calendar, so one reminder hides it in both.
///
/// The data itself is left alone — the hiding happens where entries are
/// shown or counted. Taking entries out of the stored days would make the
/// app think they were deleted.
library;

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';

const hideMarker = "#dr-hide";

/// Whether a reminder's text is a hiding marker.
bool isHideMarkerText(String? text) =>
    text != null && text.startsWith("$hideMarker ");

bool isHideMarker(Homework entry) =>
    entry.type == HomeworkType.homework && isHideMarkerText(entry.subtitle);

/// The key of a marker's entry: "gradeGroup:2244".
String? hiddenKeyOfMarker(String text) {
  if (!isHideMarkerText(text)) return null;
  final parts = text.substring(hideMarker.length + 1).split(" ");
  return parts.isEmpty || !parts.first.contains(":") ? null : parts.first;
}

/// The key under which [entry] can be hidden, or null for what cannot be:
/// grades, observations and one's own reminders.
String? hideKeyOf(Homework entry) {
  switch (entry.type) {
    case HomeworkType.gradeGroup:
      return "gradeGroup:${entry.id}";
    case HomeworkType.lessonHomework:
      return "lessonHomework:${entry.id}";
    default:
      return null;
  }
}

/// The calendar's test or homework is a "gradeGroup" with the same id.
String hideKeyOfExam(HomeworkExam exam) => "gradeGroup:${exam.id}";

/// The marker that hides [entry]: the key, then the entry's name, for those
/// who see the reminder on the website.
String hideMarkerText(Homework entry) {
  final what = [entry.title, entry.label]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(" ");
  final text = "$hideMarker ${hideKeyOf(entry)} (ausgeblendet: $what)";
  return text.length > 200 ? text.substring(0, 200) : text;
}

/// The hidden keys and the markers that hide them, from every loaded day.
class HiddenEntries {
  HiddenEntries(this.markers);

  static final none = HiddenEntries(const {});

  /// Key -> the reminder that hides it.
  final Map<String, Homework> markers;

  Set<String> get keys => markers.keys.toSet();

  bool get isEmpty => markers.isEmpty;

  bool hides(Homework entry) {
    final key = hideKeyOf(entry);
    return key != null && markers.containsKey(key);
  }

  bool hidesExam(HomeworkExam exam) => markers.containsKey(hideKeyOfExam(exam));

  static HiddenEntries of(DashboardState? dashboard) {
    final days = dashboard?.allDays;
    if (days == null) return none;
    final markers = <String, Homework>{};
    for (final day in days) {
      for (final entry in day.homework) {
        if (!isHideMarker(entry)) continue;
        final key = hiddenKeyOfMarker(entry.subtitle);
        if (key != null) markers[key] = entry;
      }
    }
    return HiddenEntries(markers);
  }

  /// [day] without the markers and without what they hide.
  Day visible(Day day) {
    if (!day.homework.any((e) => isHideMarker(e) || hides(e))) return day;
    return day
        .rebuild((b) => b.homework.where((e) => !isHideMarker(e) && !hides(e)));
  }

  /// What is hidden on [day].
  List<Homework> hiddenOn(Day day) => [
        for (final e in day.homework)
          if (!isHideMarker(e) && hides(e)) e
      ];

  /// [hour] without the hidden tests and homework: no red mark for them.
  CalendarHour visibleHour(CalendarHour hour) {
    if (isEmpty || !hour.homeworkExams.any(hidesExam)) return hour;
    return hour
        .rebuild((b) => b.homeworkExams.where((exam) => !hidesExam(exam)));
  }

  CalendarDay visibleCalendarDay(CalendarDay day) {
    if (isEmpty) return day;
    return day
        .rebuild((b) => b.hours = ListBuilder(day.hours.map(visibleHour)));
  }

  /// [calendar] with every day stripped of what is hidden.
  CalendarState visibleCalendar(CalendarState calendar) {
    if (isEmpty) return calendar;
    return calendar.rebuild((b) => b.days = MapBuilder({
          for (final entry in calendar.days.entries)
            entry.key: visibleCalendarDay(entry.value),
        }));
  }
}

/// For the raw answer of `api/student/dashboard/dashboard` (the evening
/// summary): the keys hidden by markers in it.
Set<String> hiddenKeysInRaw(List<dynamic>? dashboard) {
  final keys = <String>{};
  for (final dynamic day in dashboard ?? const <dynamic>[]) {
    if (day is! Map) continue;
    for (final dynamic item in day["items"] as List? ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final subtitle = item["subtitle"];
      if (subtitle is String) {
        final key = hiddenKeyOfMarker(subtitle);
        if (key != null) keys.add(key);
      }
    }
  }
  return keys;
}
