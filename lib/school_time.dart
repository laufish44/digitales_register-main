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

/// What time it is at school, and which lesson that is.
///
/// Lessons run on school time — South Tyrol, Europe/Rome — whatever time zone
/// the device happens to be set to (#21). Central European Time with the EU's
/// summer time rule is computed here rather than taken from the device.
library;

import 'dart:async';

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/widgets.dart';

/// The last Sunday of [month] in [year].
DateTime _lastSunday(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return lastDay.subtract(Duration(days: lastDay.weekday % 7));
}

/// Whether summer time is in force at [utc]: from 01:00 UTC on the last
/// Sunday of March to 01:00 UTC on the last Sunday of October.
bool isEuSummerTime(DateTime utc) {
  final start = _lastSunday(utc.year, 3).add(const Duration(hours: 1));
  final end = _lastSunday(utc.year, 10).add(const Duration(hours: 1));
  return !utc.isBefore(start) && utc.isBefore(end);
}

/// The wall-clock time at school (Europe/Rome) at [utc] (default: now).
UtcDateTime schoolNow([DateTime? utc]) {
  final at = (utc ?? DateTime.now()).toUtc();
  final local = at.add(Duration(hours: isEuSummerTime(at) ? 2 : 1));
  return UtcDateTime(local.year, local.month, local.day, local.hour,
      local.minute, local.second);
}

/// When [hour] on [day] begins and ends, from the timetable in the settings,
/// or from what the register sent when the timetable does not know it.
({UtcDateTime start, UtcDateTime end})? lessonSpan(
  UtcDateTime day,
  CalendarHour hour,
  List<LessonTime> times,
) {
  final date = UtcDateTime(day.year, day.month, day.day);
  final first = LessonTimes.forHour(times, hour.fromHour);
  final last = LessonTimes.forHour(times, hour.toHour);
  if (first != null && last != null) {
    return (
      start: date.add(Duration(minutes: first.startMinutes)),
      end: date.add(Duration(minutes: last.endMinutes)),
    );
  }
  if (hour.timeSpans.isEmpty) return null;
  return (start: hour.timeSpans.first.from, end: hour.timeSpans.last.to);
}

/// Whether [hour] on [day] is over at [now] (school time).
bool lessonIsOver(
  UtcDateTime day,
  CalendarHour hour,
  List<LessonTime> times,
  UtcDateTime now,
) {
  final span = lessonSpan(day, hour, times);
  if (span != null) return !now.isBefore(span.end);
  // No time known: a lesson of an earlier day is over all the same.
  return UtcDateTime(day.year, day.month, day.day)
      .isBefore(UtcDateTime(now.year, now.month, now.day));
}

/// A lesson going on right now.
class CurrentLesson {
  const CurrentLesson({
    required this.subject,
    required this.fromHour,
    required this.toHour,
    required this.end,
    UtcDateTime? lessonEnd,
  }) : lessonEnd = lessonEnd ?? end;

  final String subject;
  final int fromHour, toHour;

  /// When it ends — for a double lesson, the end of the second one.
  final UtcDateTime end;

  /// When the single lesson going on now ends: in the first hour of a double
  /// lesson the end of that hour, otherwise [end].
  final UtcDateTime lessonEnd;

  Duration remaining(UtcDateTime now) => end.difference(now);
  Duration remainingInLesson(UtcDateTime now) => lessonEnd.difference(now);

  /// Whether there is a later hour after the one going on now.
  bool get isDouble => lessonEnd != end;
}

/// A break longer than this splits a double lesson in two for the countdown.
const doubleLessonMaxBreak = Duration(minutes: 5);

typedef _Unit = ({int hour, UtcDateTime start, UtcDateTime end});

/// The lesson going on at [now] in [calendar], or null (break, no school,
/// calendar not loaded). Back-to-back lessons of the same subject count as
/// one: the countdown runs to the end of both (#26) — unless there is a
/// break of more than [doubleLessonMaxBreak] between them.
CurrentLesson? currentLesson(
  CalendarState calendar,
  List<LessonTime> times,
  UtcDateTime now,
) {
  final today = UtcDateTime(now.year, now.month, now.day);
  CalendarDay? day;
  for (final d in calendar.days.values) {
    if (UtcDateTime(d.date.year, d.date.month, d.date.day) == today) day = d;
  }
  if (day == null) return null;
  final hours = day.hours.toList()
    ..sort((a, b) => a.fromHour.compareTo(b.fromHour));
  var i = 0;
  while (i < hours.length) {
    // The run of back-to-back hours of the same subject starting at i.
    var k = i;
    while (k + 1 < hours.length &&
        hours[k + 1].subject == hours[i].subject &&
        hours[k + 1].fromHour == hours[k].toHour + 1) {
      k++;
    }
    final run = hours.sublist(i, k + 1);
    i = k + 1;

    final units = _units(today, run, times);
    if (units.isEmpty) continue;
    // Split where the break is too long to count as one double lesson.
    final groups = <List<_Unit>>[
      [units.first]
    ];
    for (final unit in units.skip(1)) {
      final gap = unit.start.difference(groups.last.last.end);
      if (gap > doubleLessonMaxBreak) {
        groups.add([unit]);
      } else {
        groups.last.add(unit);
      }
    }
    for (final group in groups) {
      if (now.isBefore(group.first.start) || !now.isBefore(group.last.end)) {
        continue;
      }
      return CurrentLesson(
        subject: run.first.subject,
        fromHour: group.first.hour,
        toHour: group.last.hour,
        end: group.last.end,
        lessonEnd: group.firstWhere((u) => now.isBefore(u.end)).end,
      );
    }
  }
  return null;
}

/// The break going on at [now]: after the first lesson of the day and before
/// the next one. Null outside school hours and during lessons.
({String subject, UtcDateTime start})? currentBreak(
  CalendarState calendar,
  List<LessonTime> times,
  UtcDateTime now,
) {
  final lessons = _lessonsToday(calendar, times, now);
  if (lessons.isEmpty) return null;
  if (!lessons.any((l) => !now.isBefore(l.unit.end))) return null;
  if (lessons
      .any((l) => !now.isBefore(l.unit.start) && now.isBefore(l.unit.end))) {
    return null;
  }
  for (final lesson in lessons) {
    if (lesson.unit.start.isAfter(now)) {
      return (subject: lesson.subject, start: lesson.unit.start);
    }
  }
  return null;
}

/// When the last lesson of today ends, while school is on (from the start of
/// the first lesson until then); otherwise null.
UtcDateTime? schoolEnd(
  CalendarState calendar,
  List<LessonTime> times,
  UtcDateTime now,
) {
  final lessons = _lessonsToday(calendar, times, now);
  if (lessons.isEmpty) return null;
  final end =
      lessons.map((l) => l.unit.end).reduce((a, b) => a.isAfter(b) ? a : b);
  if (now.isBefore(lessons.first.unit.start) || !now.isBefore(end)) {
    return null;
  }
  return end;
}

/// Every single lesson of today, in order.
List<({String subject, _Unit unit})> _lessonsToday(
  CalendarState calendar,
  List<LessonTime> times,
  UtcDateTime now,
) {
  final today = UtcDateTime(now.year, now.month, now.day);
  CalendarDay? day;
  for (final d in calendar.days.values) {
    if (UtcDateTime(d.date.year, d.date.month, d.date.day) == today) day = d;
  }
  if (day == null) return const [];
  return [
    for (final hour in day.hours)
      for (final unit in _units(today, [hour], times))
        (subject: hour.subject, unit: unit),
  ]..sort((a, b) => a.unit.start.compareTo(b.unit.start));
}

/// The single lessons of [run], each with its own times when the timetable
/// knows them all; otherwise each calendar hour as one piece.
List<_Unit> _units(
    UtcDateTime today, List<CalendarHour> run, List<LessonTime> times) {
  final perHour = <_Unit>[];
  for (final hour in run) {
    for (var h = hour.fromHour; h <= hour.toHour; h++) {
      final time = LessonTimes.forHour(times, h);
      if (time == null) {
        perHour.clear();
        break;
      }
      perHour.add((
        hour: h,
        start: today.add(Duration(minutes: time.startMinutes)),
        end: today.add(Duration(minutes: time.endMinutes)),
      ));
    }
    if (perHour.isEmpty) break;
  }
  if (perHour.isNotEmpty) return perHour;
  return [
    for (final hour in run)
      if (lessonSpan(today, hour, times) case final span?)
        (hour: hour.fromHour, start: span.start, end: span.end),
  ];
}

/// Rebuilds [builder] every [interval] with the school time.
class SchoolClock extends StatefulWidget {
  const SchoolClock({
    super.key,
    required this.builder,
    this.interval = const Duration(seconds: 30),
  });

  final Widget Function(BuildContext context, UtcDateTime now) builder;
  final Duration interval;

  @override
  State<SchoolClock> createState() => _SchoolClockState();
}

class _SchoolClockState extends State<SchoolClock> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, schoolNow());
}
