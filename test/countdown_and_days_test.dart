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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/school_time.dart';
import 'package:dr/ui/current_lesson.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

LessonTime _time(int hour, int start) => LessonTime((b) => b
  ..hour = hour
  ..startMinutes = start
  ..endMinutes = start + 50);

CalendarHour _hour(int from, int to, String subject) => CalendarHour(
      (b) => b
        ..fromHour = from
        ..toHour = to
        ..subject = subject
        ..timeSpans = ListBuilder<TimeSpan>()
        ..rooms = ListBuilder<String>()
        ..teachers = ListBuilder<Teacher>()
        ..homeworkExams = ListBuilder<HomeworkExam>()
        ..lessonContents = ListBuilder<LessonContent>(),
    );

final _day = UtcDateTime(2026, 11, 10);

CalendarState _calendar(List<CalendarHour> hours) => CalendarState((b) => b
  ..days = MapBuilder({
    _day: CalendarDay((b) => b
      ..date = _day
      ..hours = ListBuilder(hours)),
  }));

UtcDateTime _at(int h, int m) => UtcDateTime(2026, 11, 10, h, m);

void main() {
  // 1st 07:45–08:35, 2nd 08:35–09:25, 3rd 09:40–10:30 (15 min break),
  // 4th 10:35–11:25 (5 min break).
  final times = [
    _time(1, 465),
    _time(2, 515),
    _time(3, 580),
    _time(4, 635),
  ];

  group("countdown for double lessons", () {
    test("shows the end of the first hour in brackets", () {
      final lesson = currentLesson(
          _calendar([_hour(1, 2, "Mathematik")]), times, _at(8, 0))!;
      expect(lesson.end, _at(9, 25));
      expect(lesson.lessonEnd, _at(8, 35));
      expect(CurrentLessonChip.label("Mat", lesson, _at(8, 0)),
          "Mat · noch 1:25:00 (35:00)");
    });

    test("no brackets in the second hour", () {
      final lesson = currentLesson(
          _calendar([_hour(1, 1, "Mathematik"), _hour(2, 2, "Mathematik")]),
          times,
          _at(9, 0))!;
      expect(lesson.isDouble, isFalse);
      expect(CurrentLessonChip.label("Mat", lesson, _at(9, 0)),
          "Mat · noch 25:00");
    });

    test("a break of more than 5 minutes splits it", () {
      final calendar = _calendar([_hour(2, 3, "Deutsch")]);
      final second = currentLesson(calendar, times, _at(9, 0))!;
      expect(second.end, _at(9, 25));
      expect(second.isDouble, isFalse);
      expect(currentLesson(calendar, times, _at(9, 30)), isNull);
      final third = currentLesson(calendar, times, _at(9, 45))!;
      expect(third.fromHour, 3);
      expect(third.end, _at(10, 30));
    });

    test("a break of exactly 5 minutes does not", () {
      final calendar =
          _calendar([_hour(3, 3, "Englisch"), _hour(4, 4, "Englisch")]);
      final lesson = currentLesson(calendar, times, _at(10, 0))!;
      expect(lesson.end, _at(11, 25));
      expect(lesson.lessonEnd, _at(10, 30));
      // In the short break the next hour is what is left.
      final inBreak = currentLesson(calendar, times, _at(10, 32))!;
      expect(inBreak.end, _at(11, 25));
      expect(inBreak.isDouble, isFalse);
    });
  });

  group("day headings in the register", () {
    final christmas = HolidayPeriod((b) => b
      ..name = "Weihnachtsferien"
      ..start = UtcDateTime(2026, 12, 24)
      ..end = UtcDateTime(2027, 1, 6));

    test("holidays have their name, weekends are only muted", () {
      expect(dayKind(UtcDateTime(2026, 12, 28), [christmas]).label,
          "Weihnachtsferien");
      // A Saturday in the holidays counts as holidays.
      expect(dayKind(UtcDateTime(2026, 12, 26), [christmas]).isHoliday, isTrue);
      expect(dayKind(UtcDateTime(2026, 11, 14), [christmas]), DayKind.weekend);
      expect(dayKind(UtcDateTime(2026, 11, 13), [christmas]), DayKind.school);
    });
  });
}
