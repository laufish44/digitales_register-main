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

/// When the lessons of a day run.
///
/// The register does report real times — every lesson in the calendar carries a
/// `timeStartObject`/`timeEndObject`, which the app already parses into
/// [CalendarHour.timeSpans]. But that only covers the weeks that have been
/// fetched, and nothing at all before the calendar is opened for the first
/// time. So there is a table in the settings as well: it is what the app shows
/// when the calendar has nothing to say, and the user can correct it.
library;

import 'package:dr/app_state.dart';
import 'package:dr/utc_date_time.dart';

/// A break shorter than this is drawn as a hairline, anything longer gets a
/// visible gap. Five minutes between two lessons is "walk to the next room",
/// fifteen is a real break — they should not look the same.
const shortBreakMinutes = 10;

/// The schedule a fresh installation starts with.
///
/// Two blocks of two lessons, then the afternoon: 50 minutes each, a five
/// minute break before the third lesson and a longer one before the fifth.
/// Schools differ, which is exactly why this is editable.
final List<LessonTime> defaultLessonTimes = _build(const [
  // start, end, in minutes since midnight
  [8 * 60, 8 * 60 + 50],
  [8 * 60 + 50, 9 * 60 + 40],
  [9 * 60 + 45, 10 * 60 + 35],
  [10 * 60 + 35, 11 * 60 + 25],
  [11 * 60 + 40, 12 * 60 + 30],
  [12 * 60 + 30, 13 * 60 + 20],
  [13 * 60 + 20, 14 * 60 + 10],
  [14 * 60 + 10, 15 * 60],
  [15 * 60, 15 * 60 + 50],
  [15 * 60 + 50, 16 * 60 + 40],
]);

List<LessonTime> _build(List<List<int>> rows) => [
      for (var i = 0; i < rows.length; i++)
        LessonTime((b) => b
          ..hour = i + 1
          ..startMinutes = rows[i][0]
          ..endMinutes = rows[i][1]),
    ];

int _minutesOfDay(UtcDateTime time) => time.hour * 60 + time.minute;

class LessonTimes {
  LessonTimes._();

  /// The times the calendar actually reported, by lesson number.
  ///
  /// A lesson block spanning several lessons carries one time span per lesson,
  /// in order, so `fromHour + n` belongs to `timeSpans[n]`. Days the calendar
  /// has not seen simply contribute nothing.
  static Map<int, LessonTime> fromCalendar(CalendarState calendar) {
    final result = <int, LessonTime>{};
    for (final day in calendar.days.values) {
      for (final lesson in day.hours) {
        for (var index = 0; index < lesson.timeSpans.length; index++) {
          final hour = lesson.fromHour + index;
          if (hour > lesson.toHour) break;
          final span = lesson.timeSpans[index];
          final start = _minutesOfDay(span.from);
          final end = _minutesOfDay(span.to);
          // A span that ends before it starts crossed midnight or is broken;
          // either way it is not a school lesson.
          if (end <= start) continue;
          result.putIfAbsent(
            hour,
            () => LessonTime((b) => b
              ..hour = hour
              ..startMinutes = start
              ..endMinutes = end),
          );
        }
      }
    }
    return result;
  }

  /// The schedule to show, from the table and the calendar.
  ///
  /// [preferServer] decides which of the two is the authority; the other only
  /// fills lessons the first one does not mention at all, and only where it
  /// does not contradict it. Two lessons at the same time are never returned —
  /// the timetable has to make sense, whichever source it came from.
  ///
  /// The overlap check is not theoretical. A table that is a quarter of an hour
  /// off from what the calendar reports puts its seventh lesson on top of the
  /// calendar's eighth; without the check the app would show both.
  ///
  /// Sorted by lesson number, with no duplicates.
  static List<LessonTime> resolve({
    required Iterable<LessonTime> configured,
    required CalendarState calendar,
    bool preferServer = false,
  }) {
    final table = <int, LessonTime>{
      for (final time in configured) time.hour: time,
    };
    final server = fromCalendar(calendar);

    final authority = preferServer ? server : table;
    final filler = preferServer ? table : server;

    final result = Map.of(authority);
    for (final entry in filler.entries) {
      if (result.containsKey(entry.key)) continue;
      if (_overlapsAny(entry.value, authority.values)) continue;
      result[entry.key] = entry.value;
    }

    return result.values.toList()..sort((a, b) => a.hour.compareTo(b.hour));
  }

  static bool _overlapsAny(LessonTime time, Iterable<LessonTime> others) {
    for (final other in others) {
      if (time.startMinutes < other.endMinutes &&
          other.startMinutes < time.endMinutes) {
        return true;
      }
    }
    return false;
  }

  /// The entry for [hour], or null when nothing is known about it.
  static LessonTime? forHour(Iterable<LessonTime> times, int hour) {
    for (final time in times) {
      if (time.hour == hour) return time;
    }
    return null;
  }

  /// "3. Stunde (09:45–10:35)", or just "3. Stunde" without a known time.
  static String label(Iterable<LessonTime> times, int hour) =>
      forHour(times, hour)?.fullLabel ?? "$hour. Stunde";

  /// The break in minutes before each lesson, keyed by lesson number.
  ///
  /// The first lesson has no break before it and is left out. Used to put the
  /// same visual gaps into a list of lessons that the day actually has.
  static Map<int, int> breaksBefore(List<LessonTime> times) {
    final sorted = List.of(times)..sort((a, b) => a.hour.compareTo(b.hour));
    final result = <int, int>{};
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].startMinutes - sorted[i - 1].endMinutes;
      if (gap > 0) result[sorted[i].hour] = gap;
    }
    return result;
  }

  /// How much empty space to draw before a lesson, in logical pixels.
  ///
  /// Three steps rather than a formula, so a five minute change of the
  /// timetable cannot make the layout wobble: nothing, a hint, a real gap.
  static double spacingBefore(int? breakMinutes) {
    if (breakMinutes == null || breakMinutes <= 0) return 0;
    return breakMinutes < shortBreakMinutes ? 4 : 14;
  }

  /// The lesson running at [minutesOfDay], if any.
  static LessonTime? at(Iterable<LessonTime> times, int minutesOfDay) {
    for (final time in times) {
      if (minutesOfDay >= time.startMinutes && minutesOfDay < time.endMinutes) {
        return time;
      }
    }
    return null;
  }

  /// The highest lesson number the schedule knows.
  static int maxHour(Iterable<LessonTime> times) {
    var max = 0;
    for (final time in times) {
      if (time.hour > max) max = time.hour;
    }
    return max;
  }

  /// Renumbers and sorts, so an edited table stays consistent.
  static List<LessonTime> normalize(Iterable<LessonTime> times) {
    final sorted = List.of(times)
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return [
      for (var i = 0; i < sorted.length; i++)
        sorted[i].rebuild((b) => b..hour = i + 1),
    ];
  }
}
