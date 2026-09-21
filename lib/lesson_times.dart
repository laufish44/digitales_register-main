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
/// One source only: the table in the settings. The register does report times
/// of its own on every calendar lesson, but they are not the ones this school
/// actually keeps — they run a quarter of an hour early — so they are ignored
/// rather than mixed in. Mixing two disagreeing sources produced a timetable
/// with overlapping lessons and no obvious way to tell which one was showing.
library;

import 'package:dr/app_state.dart';

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

class LessonTimes {
  LessonTimes._();

  /// The schedule to show: the table, sorted, with nothing else mixed in.
  static List<LessonTime> resolve(Iterable<LessonTime> configured) {
    final result = List.of(configured)
      ..sort((a, b) => a.hour.compareTo(b.hour));
    return result;
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
