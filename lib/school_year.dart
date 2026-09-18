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

/// Holidays and the end of the school year.
///
/// The register's API has no endpoint for either — the web app does not show
/// them anywhere, and there is nothing in its bundle to read them from. (The
/// calendar's holiday icons are not data either: the original app just picks an
/// icon by season for any day without lessons.) They are therefore kept as an
/// editable list in the settings.
///
/// The defaults below are computed rather than typed out, so they do not go
/// stale after one year: the fixed dates are fixed, and the movable ones follow
/// Easter. Schools still deviate, so the settings page asks the user to check
/// them.
library;

import 'package:dr/app_state.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

UtcDateTime _day(int year, int month, int day) => UtcDateTime(year, month, day);

HolidayPeriod _holiday(String name, UtcDateTime start, UtcDateTime end) =>
    HolidayPeriod((b) => b
      ..name = name
      ..start = start
      ..end = end);

/// The calendar year the current school year started in.
///
/// September is the cut: from then on the new school year has begun.
int schoolYearStart(UtcDateTime date) =>
    date.month >= 9 ? date.year : date.year - 1;

/// A starting point for the school year that contains [date].
List<HolidayPeriod> holidaysForSchoolYear(UtcDateTime date) {
  final first = schoolYearStart(date);
  final second = first + 1;
  final easter = calculateEaster(second);

  // Rosenmontag is 48 days before Easter, and the winter break is that whole
  // week from Monday to Friday.
  final carnivalMonday = easter.subtract(const Duration(days: 48));

  return [
    _holiday("Allerheiligen", _day(first, 10, 31), _day(first, 11, 2)),
    _holiday("Weihnachtsferien", _day(first, 12, 24), _day(second, 1, 6)),
    _holiday(
      "Winterferien",
      carnivalMonday,
      carnivalMonday.add(const Duration(days: 4)),
    ),
    // Maundy Thursday to the Tuesday after Easter.
    _holiday(
      "Osterferien",
      easter.subtract(const Duration(days: 3)),
      easter.add(const Duration(days: 2)),
    ),
    _holiday("Staatsfeiertag", _day(second, 4, 25), _day(second, 4, 25)),
    _holiday("Tag der Arbeit", _day(second, 5, 1), _day(second, 5, 1)),
  ];
}

/// The holidays a fresh installation starts with.
List<HolidayPeriod> get defaultHolidays => holidaysForSchoolYear(now);

/// The default last day of school: mid June of the second half of the year.
///
/// The one date here that really is a guess — the exact day is decided per
/// school.
UtcDateTime get defaultLastSchoolDay => _day(schoolYearStart(now) + 1, 6, 16);

/// The date of Easter Sunday.
// https://en.wikipedia.org/wiki/Date_of_Easter#Meeus.27s_Julian_algorithm
UtcDateTime calculateEaster(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final g = (8 * b + 13) ~/ 25;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 19 * l) ~/ 433;
  final n = (h + l - 7 * m + 90) ~/ 25;
  final p = (h + l - 7 * m + 33 * n + 19) % 32;
  return UtcDateTime(year, n, p);
}

/// What the sidebar counts down to.
class Countdown {
  const Countdown({
    required this.label,
    required this.date,
    required this.days,
    this.ongoing = false,
  });

  /// "Weihnachtsferien", "Schulende", …
  final String label;

  /// The day the countdown points at — the first day of the holidays, or the
  /// last day of school.
  final UtcDateTime date;

  /// Whole days from today. Zero means it starts today.
  final int days;

  /// True while the holidays are running right now.
  final bool ongoing;

  String get daysLabel {
    if (ongoing) return "läuft";
    if (days <= 0) return "heute";
    if (days == 1) return "morgen";
    return "$days Tage";
  }
}

class SchoolYear {
  SchoolYear._();

  /// The next holidays from [now] on, or the ones running right now.
  ///
  /// Periods that are entirely in the past are skipped, so an outdated list
  /// simply stops producing a countdown instead of showing nonsense.
  static Countdown? nextHolidays(
    Iterable<HolidayPeriod> holidays, {
    required UtcDateTime now,
  }) {
    final today = UtcDateTime(now.year, now.month, now.day);
    HolidayPeriod? best;
    for (final holiday in holidays) {
      if (holiday.end.isBefore(today)) continue;
      if (best == null || holiday.start.isBefore(best.start)) best = holiday;
    }
    if (best == null) return null;

    final ongoing = best.contains(today);
    return Countdown(
      label: best.name,
      date: best.start,
      days: best.start.difference(today).inDays,
      ongoing: ongoing,
    );
  }

  /// The countdown to the last day of school, or null once it has passed.
  static Countdown? lastDay(UtcDateTime? lastSchoolDay,
      {required UtcDateTime now}) {
    if (lastSchoolDay == null) return null;
    final today = UtcDateTime(now.year, now.month, now.day);
    final last = UtcDateTime(
        lastSchoolDay.year, lastSchoolDay.month, lastSchoolDay.day);
    if (last.isBefore(today)) return null;
    return Countdown(
      label: "Schulende",
      date: last,
      days: last.difference(today).inDays,
    );
  }

  /// The number of school days between [from] and [to], both inclusive.
  ///
  /// Weekends and the [holidays] do not count. Used to turn "x hours left" into
  /// "that is y per week".
  static int schoolDaysBetween(
    UtcDateTime from,
    UtcDateTime to, {
    Iterable<HolidayPeriod> holidays = const [],
    bool saturdayIsSchoolDay = false,
  }) {
    if (to.isBefore(from)) return 0;
    var day = UtcDateTime(from.year, from.month, from.day);
    final end = UtcDateTime(to.year, to.month, to.day);
    var count = 0;
    while (!day.isAfter(end)) {
      final isWeekend = day.weekday == DateTime.sunday ||
          (day.weekday == DateTime.saturday && !saturdayIsSchoolDay);
      if (!isWeekend && !holidays.any((h) => h.contains(day))) count++;
      day = day.add(const Duration(days: 1));
    }
    return count;
  }
}
