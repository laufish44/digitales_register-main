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
import 'package:dr/hidden_entries.dart';
import 'package:dr/notifications/summaries.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

Homework _test(int id, {String label = "Mathematik"}) => Homework((b) => b
  ..id = id
  ..title = "Schularbeit"
  ..subtitle = "1. Schularbeit"
  ..label = label
  ..type = HomeworkType.gradeGroup
  ..warning = true
  ..checkable = true
  ..checked = false);

Homework _reminder(int id, String text) => Homework((b) => b
  ..id = id
  ..title = "Erinnerung"
  ..subtitle = text
  ..type = HomeworkType.homework
  ..checkable = true
  ..checked = false
  ..deleteable = true);

Day _day(UtcDateTime date, List<Homework> entries) => Day((b) => b
  ..date = date
  ..lastRequested = date
  ..homework = ListBuilder(entries)
  ..deletedHomework = ListBuilder<Homework>());

HomeworkExam _exam(int id) => HomeworkExam((b) => b
  ..id = id
  ..name = "1. Schularbeit"
  ..homework = false
  ..online = false
  ..deadline = UtcDateTime(2026, 11, 20, 7, 45)
  ..hasGrades = false
  ..hasGradeGroupSubmissions = false
  ..typeId = 2
  ..typeName = "Schularbeit"
  ..warning = true);

void main() {
  final friday = UtcDateTime(2026, 11, 20);
  final monday = UtcDateTime(2026, 11, 23);
  final hiddenTest = _test(2244);
  final otherTest = _test(2250, label: "Deutsch");
  final marker = _reminder(9000, hideMarkerText(hiddenTest));
  final dashboard = DashboardState((b) => b
    ..allDays = ListBuilder([
      _day(friday, [hiddenTest, marker]),
      _day(monday, [otherTest]),
    ])
    ..future = true
    ..loading = false
    ..blacklist = ListBuilder<HomeworkType>());

  test("the marker names the entry by type and id", () {
    expect(marker.subtitle,
        startsWith("#dr-hide gradeGroup:2244 (ausgeblendet: Schularbeit"));
    expect(hiddenKeyOfMarker(marker.subtitle), "gradeGroup:2244");
    expect(marker.subtitle.length, lessThanOrEqualTo(210));
    // One's own reminders and grades cannot be hidden.
    expect(hideKeyOf(_reminder(1, "Vokabeln")), isNull);
  });

  test("a hidden entry and its marker are gone from the day", () {
    final hidden = HiddenEntries.of(dashboard);
    final day = dashboard.allDays!.first;
    expect(hidden.visible(day).homework, isEmpty);
    expect(hidden.hiddenOn(day), [hiddenTest]);
    expect(hidden.markers["gradeGroup:2244"], marker);
  });

  test("it is counted nowhere", () {
    final entries = Agenda.collect(
      calendar: CalendarState(),
      dashboard: dashboard,
      includeCalendar: false,
    );
    expect(entries.map((e) => e.subject), ["Deutsch"]);
    // The marker is not a reminder of its own either.
    expect(entries.where((e) => e.isReminder), isEmpty);
    expect(WeekProgress.of(dashboard, friday), isNull);
  });

  test("the calendar loses the red mark for it", () {
    final hour = CalendarHour((b) => b
      ..fromHour = 1
      ..toHour = 1
      ..subject = "Mathematik"
      ..timeSpans = ListBuilder<TimeSpan>()
      ..rooms = ListBuilder<String>()
      ..teachers = ListBuilder<Teacher>()
      ..homeworkExams = ListBuilder([_exam(2244)])
      ..lessonContents = ListBuilder<LessonContent>());
    expect(hour.warning, isTrue);
    final visible = HiddenEntries.of(dashboard).visibleHour(hour);
    expect(visible.warning, isFalse);
    expect(visible.homeworkExams, isEmpty);
  });

  test("the evening summary leaves it out", () {
    final raw = [
      {
        "date": "2026-11-20",
        "items": [
          {
            "id": 2244,
            "type": "gradeGroup",
            "title": "Schularbeit",
            "label": "Mathematik",
            "homework": 0
          },
          {"id": 9000, "type": "homework", "subtitle": marker.subtitle},
        ],
      },
    ];
    expect(
      EveningSummary.compose(day: friday, dashboard: raw, calendar: null),
      isNull,
    );
  });
}
