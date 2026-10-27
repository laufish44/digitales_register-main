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
  });

  final String subject;
  final int fromHour, toHour;

  /// When it ends — for a double lesson, the end of the second one.
  final UtcDateTime end;

  Duration remaining(UtcDateTime now) => end.difference(now);
}

/// The lesson going on at [now] in [calendar], or null (break, no school,
/// calendar not loaded). Back-to-back lessons of the same subject count as
/// one: the countdown runs to the end of both (#26).
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
  for (var i = 0; i < hours.length; i++) {
    final span = lessonSpan(today, hours[i], times);
    if (span == null) continue;
    if (now.isBefore(span.start) || !now.isBefore(span.end)) continue;
    var end = span.end;
    var toHour = hours[i].toHour;
    for (var j = i + 1; j < hours.length; j++) {
      final next = hours[j];
      if (next.subject != hours[i].subject || next.fromHour != toHour + 1) {
        break;
      }
      final nextSpan = lessonSpan(today, next, times);
      if (nextSpan == null) break;
      end = nextSpan.end;
      toHour = next.toHour;
    }
    return CurrentLesson(
      subject: hours[i].subject,
      fromHour: hours[i].fromHour,
      toHour: toHour,
      end: end,
    );
  }
  return null;
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
