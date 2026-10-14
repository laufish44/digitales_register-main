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

/// A school year as the school published it ("Schulkalender").
class SchoolCalendar {
  const SchoolCalendar({
    required this.firstDay,
    required this.lastDay,
    required this.holidays,
  });

  final UtcDateTime firstDay;
  final UtcDateTime lastDay;

  /// Each break runs from the first free day to the last one, weekends around
  /// it included, so "läuft" in the sidebar is true for the whole break.
  final List<HolidayPeriod> holidays;
}

/// The published calendar of the school year starting in [startYear], or null
/// for a year nobody has typed in yet (the computed defaults apply then).
///
/// 2026/27 is taken from the published Schulkalender: 7 September 2026 to
/// 16 June 2027, 174 days of school (Mo 34, Di 35, Mi 36, Do 35, Fr 34) — a
/// test counts them, so a typo cannot go unnoticed. The sheet itself prints
/// Fr 35 and 175, but the Faschingsferien start on Friday 5 February (as the
/// school confirmed), which its totals do not reflect.
SchoolCalendar? officialSchoolCalendar(int startYear) {
  switch (startYear) {
    case 2026:
      return SchoolCalendar(
        firstDay: _day(2026, 9, 7),
        lastDay: _day(2027, 6, 16),
        holidays: [
          _holiday(
              "Allerheiligenferien", _day(2026, 10, 31), _day(2026, 11, 8)),
          // Monday the 7th is a bridge day before the feast on Tuesday.
          _holiday("Maria Empfängnis", _day(2026, 12, 5), _day(2026, 12, 8)),
          _holiday("Weihnachtsferien", _day(2026, 12, 24), _day(2027, 1, 6)),
          // From the Friday after Unsinniger Donnerstag.
          _holiday("Faschingsferien", _day(2027, 2, 5), _day(2027, 2, 14)),
          _holiday("Osterferien", _day(2027, 3, 25), _day(2027, 3, 30)),
          _holiday("Pfingstmontag", _day(2027, 5, 15), _day(2027, 5, 17)),
          _holiday("Tag der Republik", _day(2027, 6, 2), _day(2027, 6, 2)),
        ],
      );
  }
  return null;
}

/// The first day of school of the school year that contains [date].
UtcDateTime firstSchoolDay(UtcDateTime date) {
  final year = schoolYearStart(date);
  final official = officialSchoolCalendar(year);
  if (official != null) return official.firstDay;
  // South Tyrol starts in the first half of September; the Monday of the week
  // with the 5th is close enough for fetching the calendar.
  return _day(year, 9, 5)
      .subtract(Duration(days: _day(year, 9, 5).weekday - 1));
}

/// The days of school from [from] to [to], both inclusive: weekdays that are
/// not part of any of the [holidays].
List<UtcDateTime> schoolDays(
  UtcDateTime from,
  UtcDateTime to, {
  Iterable<HolidayPeriod> holidays = const [],
}) {
  final result = <UtcDateTime>[];
  var day = UtcDateTime(from.year, from.month, from.day);
  final end = UtcDateTime(to.year, to.month, to.day);
  while (!day.isAfter(end)) {
    if (day.weekday <= DateTime.friday &&
        !holidays.any((h) => h.contains(day))) {
      result.add(day);
    }
    // Calendar arithmetic rather than adding 24 hours, so the loop does not
    // drift if a UtcDateTime ever carries a time.
    day = UtcDateTime(day.year, day.month, day.day + 1);
  }
  return result;
}

/// The school days of the year that contains [date], as configured: from the
/// first day of school to [lastSchoolDay], without the [holidays].
List<UtcDateTime> schoolDaysOfYear(
  UtcDateTime date, {
  required Iterable<HolidayPeriod> holidays,
  UtcDateTime? lastSchoolDay,
}) {
  final first = firstSchoolDay(date);
  var last = lastSchoolDay ?? defaultLastSchoolDayFor(date);
  // A last day from an earlier school year would count nothing at all.
  if (last.isBefore(first)) last = defaultLastSchoolDayFor(date);
  return schoolDays(first, last, holidays: holidays);
}

/// A starting point for the school year that contains [date].
List<HolidayPeriod> holidaysForSchoolYear(UtcDateTime date) {
  final first = schoolYearStart(date);
  final official = officialSchoolCalendar(first);
  if (official != null) return List.of(official.holidays);
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

/// The default last day of school: the published one, or mid June of the
/// second half of the year when no calendar for it has been typed in.
UtcDateTime get defaultLastSchoolDay => defaultLastSchoolDayFor(now);

UtcDateTime defaultLastSchoolDayFor(UtcDateTime date) {
  final year = schoolYearStart(date);
  return officialSchoolCalendar(year)?.lastDay ?? _day(year + 1, 6, 16);
}

/// Bumped whenever [officialSchoolCalendar] gains or corrects a year, so a
/// stored state with older holidays is brought up to date once, see
/// `SettingsState.schoolCalendarRevision`.
const schoolCalendarRevision = 2;

/// Whether stored [holidays] and [lastSchoolDay] belong to a school year that
/// is over (or never had any), so the defaults of the current one should
/// replace them.
bool schoolYearSettingsOutdated(
  Iterable<HolidayPeriod> holidays,
  UtcDateTime? lastSchoolDay, {
  required UtcDateTime now,
}) {
  final start = _day(schoolYearStart(now), 9, 1);
  final lastIsOld = lastSchoolDay == null || lastSchoolDay.isBefore(start);
  final holidaysAreOld = holidays.every((h) => h.end.isBefore(start));
  return lastIsOld && holidaysAreOld;
}

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
    final last =
        UtcDateTime(lastSchoolDay.year, lastSchoolDay.month, lastSchoolDay.day);
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
