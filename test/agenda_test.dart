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
import 'package:dr/reducer/settings.dart';
import 'package:dr/school_year.dart';
import 'package:dr/search.dart';
import 'package:dr/stats.dart';
import 'package:dr/update/update_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/widgets/widget_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = UtcDateTime(2026, 3, 10);

/// An entry as the dashboard delivers it.
///
/// `warning` is the register's "this is an assessment" flag — it is set from
/// `homework == 0` in the response.
Homework _dashboardEntry({
  required int id,
  required String title,
  String subject = "Mathematik",
  String subtitle = "",
  bool warning = false,
  HomeworkType type = HomeworkType.lessonHomework,
  bool deleted = false,
  bool checkable = false,
  bool checked = false,
}) =>
    Homework(
      (b) => b
        ..id = id
        ..title = title
        ..subtitle = subtitle
        ..label = subject
        ..warning = warning
        ..deleted = deleted
        ..checkable = checkable
        ..checked = checked
        ..type = type,
    );

DashboardState _dashboard(Map<UtcDateTime, List<Homework>> days) =>
    DashboardState(
      (b) => b
        ..allDays = ListBuilder([
          for (final entry in days.entries)
            Day(
              (b) => b
                ..date = entry.key
                ..homework = ListBuilder(entry.value),
            ),
        ]),
    );

HomeworkExam _calendarEntry({
  required int id,
  required String name,
  required UtcDateTime deadline,
  bool isHomework = false,
  String typeName = "Testarbeit",
}) =>
    HomeworkExam(
      (b) => b
        ..id = id
        ..name = name
        ..homework = isHomework
        ..online = false
        ..deadline = deadline
        ..hasGrades = false
        ..hasGradeGroupSubmissions = false
        ..typeId = 2
        ..typeName = typeName
        // The calendar sets this the same way: `homework == 0`.
        ..warning = !isHomework,
    );

CalendarState _calendar(Map<UtcDateTime, List<HomeworkExam>> days,
        {String subject = "Mathematik"}) =>
    CalendarState(
      (b) => b
        ..days = MapBuilder({
          for (final entry in days.entries)
            entry.key: CalendarDay(
              (b) => b
                ..date = entry.key
                ..hours = ListBuilder([
                  CalendarHour(
                    (b) => b
                      ..fromHour = 1
                      ..toHour = 1
                      ..rooms = ListBuilder<String>()
                      ..subject = subject
                      ..homeworkExams = ListBuilder(entry.value)
                      ..lessonContents = ListBuilder<LessonContent>(),
                  ),
                ]),
            ),
        }),
    );

Absence _absence(int day, int hour) => Absence(
      (b) => b
        ..minutes = 50
        ..minutesCameTooLate = 0
        ..minutesLeftTooEarly = 0
        ..date = UtcDateTime(2026, 3, day)
        ..hour = hour,
    );

AbsenceGroup _group(List<Absence> absences) => AbsenceGroup(
      (b) => b
        ..justified = AbsenceJustified.justified
        ..hours = absences.length
        ..minutes = 0
        ..absences = ListBuilder(absences),
    );

AbsenceStatistic _statistic(String percentage) =>
    AbsenceStatistic((b) => b..percentage = percentage);

HolidayPeriod _holiday(String name, UtcDateTime start, UtcDateTime end) =>
    HolidayPeriod((b) => b
      ..name = name
      ..start = start
      ..end = end);

void main() {
  group("Agenda", () {
    // The bug this covers: the countdown read the calendar only, and the
    // calendar is not fetched until the calendar page asks for a week. On the
    // dashboard it was therefore always empty.
    test("finds entries the dashboard delivered, without any calendar", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(
              id: 1,
              title: "1. Schularbeit",
              warning: true,
              type: HomeworkType.gradeGroup,
            ),
          ],
        }),
        now: _today,
      );

      expect(entries, hasLength(1));
      expect(entries.single.name, "1. Schularbeit");
      expect(entries.single.isExam, isTrue);
    });

    test("leaves homework out unless it is asked for", () {
      final dashboard = _dashboard({
        UtcDateTime(2026, 3, 12): [
          _dashboardEntry(id: 1, title: "Seite 41", warning: false),
          _dashboardEntry(id: 2, title: "Test", warning: true),
        ],
      });

      final onlyExams = ExamCountdown.upcoming(CalendarState(),
          dashboard: dashboard, now: _today);
      expect(onlyExams.map((e) => e.name), ["Test"]);

      final both = ExamCountdown.upcoming(CalendarState(),
          dashboard: dashboard, now: _today, includeHomework: true);
      expect(both.map((e) => e.name), containsAll(["Test", "Seite 41"]));
    });

    test("can show homework without exams", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(id: 1, title: "Seite 41"),
            _dashboardEntry(id: 2, title: "Test", warning: true),
          ],
        }),
        now: _today,
        includeHomework: true,
        includeExams: false,
      );
      expect(entries.map((e) => e.name), ["Seite 41"]);
    });

    test("counts an exam that is today", () {
      final entries = ExamCountdown.upcoming(
        // The calendar dates an entry at the lesson, so a test at 09:20 today
        // is already "in the past" by the clock but not by the day.
        _calendar({
          _today: [
            _calendarEntry(
              id: 1,
              name: "Test",
              deadline: UtcDateTime(2026, 3, 10, 9, 20),
            ),
          ],
        }),
        now: UtcDateTime(2026, 3, 10, 12, 0),
      );
      expect(entries, hasLength(1));
      expect(entries.single.daysFrom(_today), 0);
    });

    test("includes the last day of the window", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 17): [
            _dashboardEntry(id: 1, title: "Test", warning: true),
          ],
        }),
        now: _today,
        within: const Duration(days: 7),
      );
      expect(entries, hasLength(1));
    });

    test("drops what is already past", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 9): [
            _dashboardEntry(id: 1, title: "Test", warning: true),
          ],
        }),
        now: _today,
      );
      expect(entries, isEmpty);
    });

    test("reports the same entry once when both sources have it", () {
      final entries = ExamCountdown.upcoming(
        _calendar({
          UtcDateTime(2026, 3, 12): [
            _calendarEntry(
              id: 7,
              name: "1. Schularbeit",
              deadline: UtcDateTime(2026, 3, 12, 9, 20),
            ),
          ],
        }),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(
              id: 7,
              title: "1. Schularbeit",
              warning: true,
              type: HomeworkType.gradeGroup,
            ),
          ],
        }),
        now: _today,
      );
      expect(entries, hasLength(1));
    });

    test("ignores grades, observations and deleted entries", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(
                id: 1, title: "Note", warning: true, type: HomeworkType.grade),
            _dashboardEntry(
              id: 2,
              title: "Beobachtung",
              warning: true,
              type: HomeworkType.observation,
            ),
            _dashboardEntry(
                id: 3, title: "Gelöscht", warning: true, deleted: true),
          ],
        }),
        now: _today,
        includeHomework: true,
      );
      expect(entries, isEmpty);
    });

    test("drops what has been ticked off", () {
      final dashboard = _dashboard({
        UtcDateTime(2026, 3, 12): [
          _dashboardEntry(
              id: 1, title: "Erledigt", checkable: true, checked: true),
          _dashboardEntry(id: 2, title: "Offen", checkable: true),
        ],
      });

      final entries = ExamCountdown.upcoming(CalendarState(),
          dashboard: dashboard, now: _today, includeHomework: true);
      expect(entries.map((e) => e.name), ["Offen"]);

      // Still reachable when something explicitly wants everything.
      final withDone = ExamCountdown.upcoming(CalendarState(),
          dashboard: dashboard,
          now: _today,
          includeHomework: true,
          includeDone: true);
      expect(withDone.map((e) => e.name), containsAll(["Offen", "Erledigt"]));
    });

    test("a tick removes the calendar's copy of the same entry too", () {
      // The dashboard carries the tick, the calendar does not - without
      // matching them by identity the entry would survive in the calendar copy.
      final entries = ExamCountdown.upcoming(
        _calendar({
          UtcDateTime(2026, 3, 12): [
            _calendarEntry(
              id: 7,
              name: "Seite 41",
              deadline: UtcDateTime(2026, 3, 12, 9, 20),
              isHomework: true,
            ),
          ],
        }),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(
                id: 7, title: "Seite 41", checkable: true, checked: true),
          ],
        }),
        now: _today,
        includeHomework: true,
      );
      expect(entries, isEmpty);
    });

    test("an unticked checkable entry stays", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(id: 1, title: "Offen", checkable: true),
          ],
        }),
        now: _today,
        includeHomework: true,
      );
      expect(entries, hasLength(1));
    });

    test("forDay drops ticked entries as well", () {
      final tomorrow = Agenda.forDay(
        calendar: CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 11): [
            _dashboardEntry(
                id: 1, title: "Erledigt", checkable: true, checked: true),
            _dashboardEntry(id: 2, title: "Offen"),
          ],
        }),
        day: UtcDateTime(2026, 3, 11),
      );
      expect(tomorrow.map((e) => e.name), ["Offen"]);
    });

    test("forDay picks exactly that day", () {
      final dashboard = _dashboard({
        UtcDateTime(2026, 3, 10): [_dashboardEntry(id: 1, title: "Heute")],
        UtcDateTime(2026, 3, 11): [_dashboardEntry(id: 2, title: "Morgen")],
      });
      final tomorrow = Agenda.forDay(
        calendar: CalendarState(),
        dashboard: dashboard,
        day: UtcDateTime(2026, 3, 11),
      );
      expect(tomorrow.map((e) => e.name), ["Morgen"]);
    });

    test("lessonsOn returns the lessons of that day in order", () {
      final calendar = _calendar({_today: const []});
      expect(Agenda.lessonsOn(calendar, _today), hasLength(1));
      expect(Agenda.lessonsOn(calendar, UtcDateTime(2026, 3, 11)), isEmpty);
    });

    test("sorts by deadline", () {
      final entries = ExamCountdown.upcoming(
        CalendarState(),
        dashboard: _dashboard({
          UtcDateTime(2026, 3, 20): [
            _dashboardEntry(id: 1, title: "Später", warning: true)
          ],
          UtcDateTime(2026, 3, 12): [
            _dashboardEntry(id: 2, title: "Früher", warning: true)
          ],
        }),
        now: _today,
        within: const Duration(days: 30),
      );
      expect(entries.map((e) => e.name), ["Früher", "Später"]);
    });
  });

  group("AbsenceStats budget", () {
    test("works the total back from the percentage", () {
      // 12 missed lessons are 2.5 % -> the year has 480.
      final budget = AbsenceStats.budget(
        statistic: _statistic("2,5"),
        absences: [_group(List.generate(12, (i) => _absence(2, i + 1)))],
        limitPercentage: 20,
      );
      expect(budget, isNotNull);
      expect(budget!.estimatedTotalLessons, closeTo(480, 0.01));
      expect(budget.allowedLessons, closeTo(96, 0.01));
      expect(budget.remainingLessons, closeTo(84, 0.01));
      expect(budget.exceeded, isFalse);
    });

    test("notices when the limit is already passed", () {
      final budget = AbsenceStats.budget(
        statistic: _statistic("25"),
        absences: [_group(List.generate(10, (i) => _absence(2, i + 1)))],
        limitPercentage: 20,
      );
      expect(budget!.exceeded, isTrue);
      expect(budget.remainingLessons, lessThan(0));
    });

    test("gives up rather than guessing when there is no percentage", () {
      expect(
        AbsenceStats.budget(
          statistic: null,
          absences: [_group([_absence(2, 1)])],
          limitPercentage: 20,
        ),
        isNull,
      );
    });

    test("counts late arrivals as part of a lesson", () {
      final partial = AbsenceGroup(
        (b) => b
          ..justified = AbsenceJustified.justified
          ..hours = 0
          ..minutes = 25
          ..absences = ListBuilder([
            Absence(
              (b) => b
                ..minutes = 25
                ..minutesCameTooLate = 25
                ..minutesLeftTooEarly = 0
                ..date = UtcDateTime(2026, 3, 2)
                ..hour = 1,
            ),
          ]),
      );
      expect(AbsenceStats.missedLessons([partial]), closeTo(0.5, 0.001));
    });

    test("finds the lesson and the weekday that are missed most", () {
      final groups = [
        _group([_absence(2, 1), _absence(3, 1), _absence(4, 5)]),
      ];
      final byLesson = AbsenceStats.missedByLesson(groups);
      expect(byLesson[1], 2);
      expect(byLesson[5], 1);
      // 2 March 2026 is a Monday.
      expect(AbsenceStats.missedByWeekday(groups)[DateTime.monday], 1);
      expect(AbsenceStats.share(2, 3), closeTo(66.67, 0.01));
    });

    test("attributes missed lessons to subjects the calendar knows", () {
      final result = AbsenceStats.missedBySubject(
        absences: [
          _group([
            Absence(
              (b) => b
                ..minutes = 50
                ..minutesCameTooLate = 0
                ..minutesLeftTooEarly = 0
                ..date = _today
                ..hour = 1,
            ),
            // No calendar entry for this one.
            _absence(28, 4),
          ]),
        ],
        calendar: _calendar({_today: const []}, subject: "Latein"),
      );
      expect(result.bySubject["Latein"], 1);
      expect(result.unmatched, 1);
    });
  });

  group("SchoolYear", () {
    final holidays = [
      _holiday("Osterferien", UtcDateTime(2026, 4, 2), UtcDateTime(2026, 4, 7)),
      _holiday("Weihnachten", UtcDateTime(2025, 12, 24),
          UtcDateTime(2026, 1, 6)),
    ];

    test("counts down to the next holidays and skips the past ones", () {
      final next = SchoolYear.nextHolidays(holidays, now: _today);
      expect(next!.label, "Osterferien");
      expect(next.days, 23);
      expect(next.ongoing, isFalse);
    });

    test("says so while the holidays are running", () {
      final next =
          SchoolYear.nextHolidays(holidays, now: UtcDateTime(2026, 4, 4));
      expect(next!.ongoing, isTrue);
      expect(next.daysLabel, "läuft");
    });

    test("returns nothing once everything is in the past", () {
      expect(
        SchoolYear.nextHolidays(holidays, now: UtcDateTime(2026, 7, 1)),
        isNull,
      );
    });

    test("counts down to the last day of school", () {
      final last =
          SchoolYear.lastDay(UtcDateTime(2026, 6, 16), now: _today);
      expect(last!.days, 98);
      expect(SchoolYear.lastDay(UtcDateTime(2026, 1, 1), now: _today), isNull);
    });

    test("knows when Easter is", () {
      expect(calculateEaster(2026), UtcDateTime(2026, 4, 5));
      expect(calculateEaster(2027), UtcDateTime(2027, 3, 28));
    });

    test("the school year turns over in September", () {
      expect(schoolYearStart(UtcDateTime(2026, 9, 18)), 2026);
      expect(schoolYearStart(UtcDateTime(2026, 8, 31)), 2025);
    });

    test("the default holidays follow the year they are asked for", () {
      final holidays = holidaysForSchoolYear(UtcDateTime(2026, 9, 18));
      final byName = {for (final h in holidays) h.name: h};

      expect(byName["Weihnachtsferien"]!.start, UtcDateTime(2026, 12, 24));
      expect(byName["Weihnachtsferien"]!.end, UtcDateTime(2027, 1, 6));
      // Easter 2027 is 28 March, so the break runs Maundy Thursday to the
      // Tuesday after.
      expect(byName["Osterferien"]!.start, UtcDateTime(2027, 3, 25));
      expect(byName["Osterferien"]!.end, UtcDateTime(2027, 3, 30));
      // Rosenmontag 2027 is 8 February.
      expect(byName["Winterferien"]!.start, UtcDateTime(2027, 2, 8));
      expect(byName["Winterferien"]!.start.weekday, DateTime.monday);
      expect(byName["Winterferien"]!.end, UtcDateTime(2027, 2, 12));
    });

    test("counts school days without weekends and holidays", () {
      // 30 March to 10 April 2026: ten weekdays, six of them Easter holidays.
      expect(
        SchoolYear.schoolDaysBetween(
          UtcDateTime(2026, 3, 30),
          UtcDateTime(2026, 4, 10),
          holidays: holidays,
        ),
        6,
      );
    });
  });

  group("UpdateService GitHub addresses", () {
    test("turns a repository address into the API address", () {
      expect(
        UpdateService.gitHubApiUri("https://github.com/miDeb/digitales_register")
            .toString(),
        "https://api.github.com/repos/miDeb/digitales_register/releases/latest",
      );
    });

    test("accepts the releases page and a missing scheme", () {
      expect(
        UpdateService.gitHubApiUri("github.com/user/repo/releases")?.path,
        "/repos/user/repo/releases/latest",
      );
      expect(
        UpdateService.gitHubApiUri("https://github.com/user/repo.git/")?.path,
        "/repos/user/repo/releases/latest",
      );
    });

    test("leaves an API address alone", () {
      const api = "https://api.github.com/repos/user/repo/releases/latest";
      expect(UpdateService.gitHubApiUri(api).toString(), api);
    });

    test("is not fooled by something that is not GitHub", () {
      expect(UpdateService.gitHubApiUri("https://example.org/releases"), isNull);
      expect(UpdateService.gitHubApiUri(""), isNull);
      expect(UpdateService.gitHubApiUri("https://github.com/user"), isNull);
    });
  });

  group("search", () {
    test("ranks an exact match above a prefix above a substring", () {
      final exact = scoreMatch("Mathematik", "Mathematik")!;
      final prefix = scoreMatch("Mathematik", "Mathe")!;
      final inside = scoreMatch("Informatik", "matik")!;
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(inside));
    });

    test("matches regardless of case", () {
      expect(scoreMatch("Deutsch", "deutsch"), isNotNull);
    });

    test("falls back to a subsequence, but only for longer queries", () {
      expect(scoreMatch("Michael Debertol", "mdb"), isNotNull);
      expect(scoreMatch("Michael Debertol", "md"), isNull);
    });

    test("says no when the letters are not there", () {
      expect(scoreMatch("Mathematik", "xyz"), isNull);
      expect(scoreMatch("Mathematik", ""), isNull);
    });
  });

  group("dashboard widgets", () {
    test("every type has a default configuration", () {
      final defaults = defaultDashboardWidgets;
      expect(defaults, hasLength(dashboardWidgetTypes.length));
      for (final type in dashboardWidgetTypes) {
        expect(defaults.any((c) => c.type == type.id), isTrue,
            reason: "no default for ${type.id}");
      }
    });

    test("widget ids are unique", () {
      final ids = dashboardWidgetTypes.map((t) => t.id).toSet();
      expect(ids, hasLength(dashboardWidgetTypes.length));
    });

    test("the upcoming card leaves homework out by default", () {
      final upcoming =
          defaultDashboardWidgets.firstWhere((c) => c.type == upcomingWidgetId);
      expect(upcoming.includeHomework, isFalse);
      expect(upcoming.includeExams, isTrue);
      expect(upcoming.enabled, isTrue);
    });

    test("reconciling adds new types and drops unknown ones", () {
      final stored = BuiltList<DashboardWidgetConfig>([
        DashboardWidgetConfig((b) => b
          ..type = tomorrowWidgetId
          ..enabled = false),
        DashboardWidgetConfig((b) => b..type = "gibt-es-nicht-mehr"),
      ]);

      final reconciled = reconcileDashboardWidgets(stored);
      expect(reconciled.any((c) => c.type == "gibt-es-nicht-mehr"), isFalse);
      expect(reconciled, hasLength(dashboardWidgetTypes.length));
      // The user's own setting survives, and their order comes first.
      expect(reconciled.first.type, tomorrowWidgetId);
      expect(reconciled.first.enabled, isFalse);
    });
  });
}
