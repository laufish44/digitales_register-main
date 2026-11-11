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
import 'package:dr/notifications/summaries.dart';
import 'package:dr/school_time.dart';
import 'package:dr/stats.dart';
import 'package:dr/ui/compact_days.dart';
import 'package:dr/ui/current_lesson.dart';
import 'package:dr/ui/message_compose.dart';
import 'package:dr/ui/year_review.dart';
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

Homework _entry(
  String title, {
  HomeworkType type = HomeworkType.gradeGroup,
  bool warning = false,
  bool checkable = true,
  bool checked = false,
  String label = "Mathematik",
}) =>
    Homework((b) => b
      ..id = title.hashCode
      ..title = title
      ..subtitle = ""
      ..label = label
      ..type = type
      ..warning = warning
      ..checkable = checkable
      ..checked = checked);

Day _dashDay(UtcDateTime date, List<Homework> entries) => Day((b) => b
  ..date = date
  ..lastRequested = date
  ..homework = ListBuilder(entries)
  ..deletedHomework = ListBuilder<Homework>());

void main() {
  // 1st 07:45–08:35, 2nd 08:35–09:25, 3rd 09:40–10:30.
  final times = [_time(1, 465), _time(2, 515), _time(3, 580)];
  final calendar = _calendar([
    _hour(1, 1, "Mathematik"),
    _hour(3, 3, "Italienisch"),
  ]);

  group("break and school end (1, 2)", () {
    test("a break counts down to the next lesson", () {
      final pause = currentBreak(calendar, times, _at(9, 0))!;
      expect(pause.subject, "Italienisch");
      expect(pause.start, _at(9, 40));
      expect(
          breakLabel(
              "Ita", pause.start, UtcDateTime(2026, 11, 10, 9, 31, 30), null),
          "Pause · noch 8:30 → Ita");
    });

    test("no break before school or during a lesson", () {
      expect(currentBreak(calendar, times, _at(7, 30)), isNull);
      expect(currentBreak(calendar, times, _at(8, 0)), isNull);
      expect(currentBreak(calendar, times, _at(11, 0)), isNull);
    });

    test("school ends with the last lesson", () {
      expect(schoolEnd(calendar, times, _at(8, 0)), _at(10, 30));
      expect(schoolEnd(calendar, times, _at(10, 31)), isNull);
      expect(
          schoolEndLabel(_at(10, 30), _at(8, 15)), "Schulschluss in 2:15:00");
    });
  });

  group("evening summary (4)", () {
    final tomorrow = UtcDateTime(2026, 11, 11);
    final dashboard = [
      {
        "date": "2026-11-11",
        "items": [
          {
            "type": "gradeGroup",
            "title": "Test",
            "label": "Deutsch",
            "homework": 0,
          },
          {
            "type": "gradeGroup",
            "title": "Hausaufgabe",
            "label": "Italienisch",
            "homework": 1,
          },
          {"type": "homework", "subtitle": "Turnsachen"},
        ],
      },
      {"date": "2026-11-12", "items": <dynamic>[]},
    ];

    test("lists tests, homework and reminders", () {
      final summary = EveningSummary.compose(
        day: tomorrow,
        dashboard: dashboard,
        calendar: null,
        nicks: const {"Deutsch": "Deu", "Italienisch": "Ita"},
      )!;
      expect(summary.title, "Morgen, Mittwoch 11.11.");
      expect(summary.body, "Test in Deu · Hausaufgabe in Ita · 1 Erinnerung");
    });

    test("nothing on a day without school or entries", () {
      expect(
        EveningSummary.compose(
          day: UtcDateTime(2026, 11, 12),
          dashboard: dashboard,
          calendar: null,
        ),
        isNull,
      );
    });
  });

  group("new grade with the average (18)", () {
    Map<String, dynamic> grade(String g, String created) => {
          "grade": g,
          "weight": 100,
          "date": "2026-10-19",
          "type": "Test",
          "cancelled": 0,
          "createdTimeStamp": created,
        };
    final allSubjects = {
      "subjects": [
        {
          "subject": {"id": 7, "name": "Mathematik"},
          "grades": [
            grade("7.00", "2026-10-01 10:00:00"),
            grade("8.00", "2026-10-02 10:00:00"),
            grade("9.00", "2026-11-09 10:00:00"),
          ],
        },
      ],
    };

    test("the newest grade moves the average", () {
      final change = averageChange(allSubjects, 7)!;
      expect(change.subject, "Mathematik");
      expect(formatAverageChange(change), "Schnitt 7,50 → 8,00");
    });

    test("unknown subject", () {
      expect(averageChange(allSubjects, 8), isNull);
    });
  });

  group("register hints (16, 17)", () {
    final now = UtcDateTime(2026, 11, 10); // Tuesday
    final dashboard = DashboardState((b) => b
      ..allDays = ListBuilder([
        _dashDay(UtcDateTime(2026, 11, 10),
            [_entry("A", checked: true), _entry("B")]),
        _dashDay(UtcDateTime(2026, 11, 13), [_entry("C", checked: true)]),
        // Next week: not this week's progress, but three tests.
        _dashDay(UtcDateTime(2026, 11, 16), [
          _entry("Test 1", warning: true),
          _entry("Test 2", warning: true, label: "Deutsch"),
        ]),
        _dashDay(UtcDateTime(2026, 11, 18),
            [_entry("Test 3", warning: true, label: "Englisch")]),
      ])
      ..future = true
      ..loading = false
      ..blacklist = ListBuilder<HomeworkType>());

    test("this week's progress", () {
      final progress = WeekProgress.of(dashboard, now)!;
      expect(progress.done, 2);
      expect(progress.total, 3);
    });

    test("weeks with three tests or more", () {
      final weeks = ExamDensity.perWeek(
        calendar: CalendarState(),
        dashboard: dashboard,
        now: now,
      );
      expect(weeks, {UtcDateTime(2026, 11, 16): 3});
      expect(ExamDensity.weekNumber(UtcDateTime(2026, 11, 16)), 47);
    });
  });

  group("report card forecast (8)", () {
    test("rounds and marks close calls", () {
      final clear = ReportForecast.forAverage("Mat", 725);
      expect(clear.grade, 7);
      expect(clear.close, isFalse);
      final close = ReportForecast.forAverage("Deu", 655);
      expect(close.grade, 7);
      expect(close.close, isTrue);
      expect(ReportForecast.forAverage("Eng", 540).failing, isTrue);
    });
  });

  group("message drafts (15)", () {
    test("survive a round trip and empty ones are dropped", () {
      const draft = MessageDraft(
        subject: "Frage",
        text: "Hallo",
        groups: [
          {"id": 1, "type": "class"}
        ],
      );
      final back = MessageDraft.fromJson(draft.toJson())!;
      expect(back.subject, "Frage");
      expect(back.text, "Hallo");
      expect(back.groups.single["id"], 1);
      expect(const MessageDraft(subject: "x", text: " ").isEmpty, isTrue);
    });
  });

  group("overview and review (22, 24)", () {
    test("symbols by kind", () {
      expect(compactKindOf(_entry("T", warning: true)), CompactKind.test);
      expect(compactKindOf(_entry("H")), CompactKind.homework);
      expect(compactKindOf(_entry("E", type: HomeworkType.homework)),
          CompactKind.reminder);
    });

    test("the review is offered for four weeks after the last school day", () {
      final last = UtcDateTime(2027, 6, 16);
      expect(showYearReviewBanner(last, UtcDateTime(2027, 6, 15)), isFalse);
      expect(showYearReviewBanner(last, UtcDateTime(2027, 6, 16)), isTrue);
      expect(showYearReviewBanner(last, UtcDateTime(2027, 7, 20)), isFalse);
    });
  });
}
