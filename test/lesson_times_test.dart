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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = UtcDateTime(2026, 9, 14);

LessonTime _time(int hour, int startH, int startM, int endH, int endM) =>
    LessonTime((b) => b
      ..hour = hour
      ..startMinutes = startH * 60 + startM
      ..endMinutes = endH * 60 + endM);

/// A lesson block as the calendar delivers it: one time span per lesson it
/// covers, so a double lesson carries two.
CalendarHour _block({
  required int fromHour,
  required int toHour,
  required List<List<int>> spans,
  String subject = "Mathematik",
}) =>
    CalendarHour(
      (b) => b
        ..fromHour = fromHour
        ..toHour = toHour
        ..subject = subject
        ..rooms = ListBuilder<String>()
        ..homeworkExams = ListBuilder<HomeworkExam>()
        ..lessonContents = ListBuilder<LessonContent>()
        ..timeSpans = ListBuilder([
          for (final span in spans)
            TimeSpan(
              (b) => b
                ..from = UtcDateTime(
                    _day.year, _day.month, _day.day, span[0], span[1])
                ..to = UtcDateTime(
                    _day.year, _day.month, _day.day, span[2], span[3]),
            ),
        ]),
    );

CalendarState _calendar(List<CalendarHour> hours) => CalendarState(
      (b) => b
        ..days = MapBuilder({
          _day: CalendarDay(
            (b) => b
              ..date = _day
              ..hours = ListBuilder(hours),
          ),
        }),
    );

/// No two lessons may run at the same time, whatever the sources said.
void _expectNoOverlaps(List<LessonTime> times) {
  final sorted = List.of(times)
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  for (var i = 1; i < sorted.length; i++) {
    expect(
      sorted[i].startMinutes,
      greaterThanOrEqualTo(sorted[i - 1].endMinutes),
      reason: "${sorted[i - 1].fullLabel} überlappt ${sorted[i].fullLabel}",
    );
  }
}

void main() {
  group("default timetable", () {
    test("has ten lessons of fifty minutes", () {
      expect(defaultLessonTimes, hasLength(10));
      for (final lesson in defaultLessonTimes) {
        expect(lesson.lengthMinutes, 50, reason: "${lesson.hour}. Stunde");
      }
      expect(defaultLessonTimes.first.hour, 1);
      expect(defaultLessonTimes.last.hour, 10);
    });

    test("starts at eight and ends at twenty to five", () {
      expect(defaultLessonTimes.first.rangeLabel, "08:00–08:50");
      expect(defaultLessonTimes.last.rangeLabel, "15:50–16:40");
    });

    test("has a short break before the third and a long one before the fifth",
        () {
      final breaks = LessonTimes.breaksBefore(defaultLessonTimes);
      expect(breaks[2], isNull, reason: "2nd follows straight on");
      expect(breaks[3], 5);
      expect(breaks[4], isNull);
      expect(breaks[5], 15);
      expect(breaks[6], isNull);
    });

    test("the spacing matches: nothing, a hint, a real gap", () {
      final breaks = LessonTimes.breaksBefore(defaultLessonTimes);
      expect(LessonTimes.spacingBefore(breaks[2]), 0);
      final small = LessonTimes.spacingBefore(breaks[3]);
      final large = LessonTimes.spacingBefore(breaks[5]);
      expect(small, greaterThan(0));
      expect(large, greaterThan(small));
    });
  });

  group("reading the calendar", () {
    test("takes one time per lesson out of a block", () {
      // A double lesson: hours 2 and 3 in one block, two spans.
      final times = LessonTimes.fromCalendar(_calendar([
        _block(fromHour: 2, toHour: 3, spans: [
          [8, 35, 9, 25],
          [9, 30, 10, 20],
        ]),
      ]));

      expect(times[2]!.rangeLabel, "08:35–09:25");
      expect(times[3]!.rangeLabel, "09:30–10:20");
    });

    test("matches what the real register returned", () {
      // Taken from a live response of wfo-bruneck on 2026-09-14. The seventh
      // lesson is missing there because this student does not have it.
      final times = LessonTimes.fromCalendar(_calendar([
        _block(fromHour: 1, toHour: 1, spans: [
          [7, 45, 8, 35]
        ]),
        _block(fromHour: 2, toHour: 3, spans: [
          [8, 35, 9, 25],
          [9, 30, 10, 20],
        ]),
        _block(fromHour: 4, toHour: 4, spans: [
          [10, 20, 11, 10]
        ]),
        _block(fromHour: 5, toHour: 6, spans: [
          [11, 25, 12, 15],
          [12, 15, 13, 5],
        ]),
      ]));

      expect(times.keys.toList()..sort(), [1, 2, 3, 4, 5, 6]);
      expect(times[1]!.rangeLabel, "07:45–08:35");
      expect(times[5]!.rangeLabel, "11:25–12:15");
      // Same break structure as the default, a quarter of an hour earlier.
      final breaks = LessonTimes.breaksBefore(times.values.toList());
      expect(breaks[3], 5);
      expect(breaks[5], 15);
    });

    test("ignores a span that does not describe a lesson", () {
      final times = LessonTimes.fromCalendar(_calendar([
        _block(fromHour: 1, toHour: 1, spans: [
          [9, 0, 9, 0]
        ]),
      ]));
      expect(times, isEmpty);
    });

    test("does not invent lessons past the end of the block", () {
      final times = LessonTimes.fromCalendar(_calendar([
        _block(fromHour: 1, toHour: 1, spans: [
          [8, 0, 8, 50],
          [8, 50, 9, 40],
        ]),
      ]));
      expect(times.keys, [1]);
    });
  });

  group("resolve", () {
    final configured = [
      _time(1, 8, 0, 8, 50),
      _time(2, 8, 50, 9, 40),
      _time(7, 13, 20, 14, 10),
    ];

    test("the table wins by default, even where the server disagrees", () {
      final resolved = LessonTimes.resolve(
        configured: configured,
        calendar: _calendar([
          _block(fromHour: 1, toHour: 1, spans: [
            [7, 45, 8, 35]
          ]),
        ]),
      );

      expect(resolved.map((t) => t.hour), [1, 2, 7]);
      expect(resolved.first.rangeLabel, "08:00–08:50", reason: "from table");
      expect(resolved.last.rangeLabel, "13:20–14:10");
    });

    test("lets the server win when that is switched on", () {
      final resolved = LessonTimes.resolve(
        configured: configured,
        preferServer: true,
        calendar: _calendar([
          _block(fromHour: 1, toHour: 1, spans: [
            [7, 45, 8, 35]
          ]),
        ]),
      );
      expect(resolved.first.rangeLabel, "07:45–08:35");
      // The seventh is free for this student, so only the table has it.
      expect(LessonTimes.forHour(resolved, 7)!.rangeLabel, "13:20–14:10");
    });

    test("fills lessons the table does not mention at all", () {
      final resolved = LessonTimes.resolve(
        configured: configured,
        calendar: _calendar([
          _block(fromHour: 9, toHour: 9, spans: [
            [15, 0, 15, 50]
          ]),
        ]),
      );
      expect(resolved.map((t) => t.hour), [1, 2, 7, 9]);
    });

    test("never returns two lessons at the same time", () {
      // The real case: the table runs a quarter of an hour later than this
      // school, so the server's eighth lesson (13:50-14:40) sits on top of the
      // table's seventh (13:20-14:10). The table is the authority, so the
      // server's entry is the one that goes.
      final resolved = LessonTimes.resolve(
        configured: defaultLessonTimes,
        calendar: _calendar([
          _block(fromHour: 8, toHour: 8, spans: [
            [13, 50, 14, 40]
          ]),
        ]),
      );

      expect(LessonTimes.forHour(resolved, 7)!.rangeLabel, "13:20–14:10");
      expect(LessonTimes.forHour(resolved, 8)!.rangeLabel, "14:10–15:00",
          reason: "the table's own eighth, not the server's");
      _expectNoOverlaps(resolved);
    });

    test("drops a table entry the server contradicts, the other way round", () {
      final resolved = LessonTimes.resolve(
        configured: defaultLessonTimes,
        preferServer: true,
        calendar: _calendar([
          _block(fromHour: 6, toHour: 6, spans: [
            [12, 15, 13, 5]
          ]),
          _block(fromHour: 8, toHour: 8, spans: [
            [13, 50, 14, 40]
          ]),
        ]),
      );

      expect(resolved.any((t) => t.hour == 7), isFalse);
      expect(LessonTimes.label(resolved, 7), "7. Stunde");
      _expectNoOverlaps(resolved);
    });

    test("comes out sorted", () {
      final resolved = LessonTimes.resolve(
        configured: [_time(3, 9, 45, 10, 35), _time(1, 8, 0, 8, 50)],
        calendar: CalendarState(),
      );
      expect(resolved.map((t) => t.hour), [1, 3]);
    });
  });

  group("labels and lookup", () {
    final times = [_time(1, 8, 0, 8, 50), _time(3, 9, 45, 10, 35)];

    test("names a lesson with its time", () {
      expect(LessonTimes.label(times, 3), "3. Stunde (09:45–10:35)");
    });

    test("falls back to the bare number for an unknown lesson", () {
      expect(LessonTimes.label(times, 7), "7. Stunde");
    });

    test("finds the lesson running at a given moment", () {
      expect(LessonTimes.at(times, 8 * 60 + 10)?.hour, 1);
      expect(LessonTimes.at(times, 9 * 60)?.hour, isNull);
      // The end is exclusive, so the lesson is over at exactly 08:50.
      expect(LessonTimes.at(times, 8 * 60 + 50)?.hour, isNull);
    });

    test("knows the last lesson of the day", () {
      expect(LessonTimes.maxHour(times), 3);
      expect(LessonTimes.maxHour(const []), 0);
    });

    test("formats minutes with a leading zero", () {
      expect(formatMinutesOfDay(8 * 60 + 5), "08:05");
      expect(formatMinutesOfDay(0), "00:00");
      expect(formatMinutesOfDay(13 * 60 + 20), "13:20");
    });
  });

  group("normalize", () {
    test("renumbers by start time", () {
      final normalized = LessonTimes.normalize([
        _time(9, 10, 0, 10, 50),
        _time(2, 8, 0, 8, 50),
      ]);
      expect(normalized.map((t) => t.hour), [1, 2]);
      expect(normalized.first.rangeLabel, "08:00–08:50");
    });

    test("leaves an already tidy table alone", () {
      final normalized = LessonTimes.normalize(defaultLessonTimes);
      expect(normalized, defaultLessonTimes);
    });
  });
}
