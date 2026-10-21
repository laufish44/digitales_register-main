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

import 'dart:convert';
import 'dart:io';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/home_widgets.dart';
import 'package:dr/reminder_links.dart';
import 'package:dr/remote_config.dart';
import 'package:dr/school_year.dart';
import 'package:dr/update/update_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/widgets/dashboard_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = UtcDateTime(2026, 10, 21);

Homework _entry(int id, String title, HomeworkType type,
        {String subtitle = "", bool warning = false}) =>
    Homework(
      (b) => b
        ..id = id
        ..title = title
        ..subtitle = subtitle
        ..label = "Deutsch"
        ..warning = warning
        ..deleted = false
        ..checkable = true
        ..checked = false
        ..type = type,
    );

DashboardWidgetData _data(Map<UtcDateTime, List<Homework>> days) {
  final state = AppState();
  return DashboardWidgetData(
    now: _today,
    calendar: CalendarState(),
    dashboard: DashboardState(
      (b) => b
        ..allDays = ListBuilder([
          for (final entry in days.entries)
            Day((b) => b
              ..date = entry.key
              ..homework = ListBuilder(entry.value)),
        ]),
    ),
    absences: state.absencesState,
    grades: state.gradesState,
    messages: state.messagesState,
    holidays: [
      HolidayPeriod((b) => b
        ..name = "Allerheiligenferien"
        ..start = UtcDateTime(2026, 10, 31)
        ..end = UtcDateTime(2026, 11, 8)),
    ],
    lastSchoolDay: UtcDateTime(2027, 6, 16),
    absenceLimitPercentage: 10,
    weeklyLessons: 0,
    lessonTimes: const [],
  );
}

void main() {
  group("home screen widget snapshot", () {
    final exam = _entry(7, "Schularbeit", HomeworkType.gradeGroup,
        subtitle: "2. Schularbeit", warning: true);
    final data = _data({
      _today: [_entry(1, "Hausaufgabe", HomeworkType.lessonHomework)],
      UtcDateTime(2026, 10, 22): [
        exam,
        // A note to the exam: part of it, not an entry of its own.
        _entry(2, "Erinnerung", HomeworkType.homework,
            subtitle: linkedReminderText("Taschenrechner", exam)),
      ],
    });
    final snapshot = homeWidgetSnapshot(data, loggedIn: true);

    test("is plain JSON", () {
      expect(() => json.encode(snapshot), returnsNormally);
      expect(snapshot["v"], homeWidgetSnapshotVersion);
    });

    test("lists the entries per day, by date", () {
      final days = snapshot["days"]! as Map;
      final today = (days["2026-10-21"]! as Map)["entries"]! as List;
      expect(today.single, containsPair("k", "homework"));
      final tomorrow = (days["2026-10-22"]! as Map)["entries"]! as List;
      expect(tomorrow.first, containsPair("k", "exam"));
    });

    test("upcoming entries carry their date, notes to entries do not show", () {
      final upcoming = snapshot["upcoming"]! as List;
      expect(upcoming.map((e) => (e as Map)["d"]),
          containsAll(["2026-10-21", "2026-10-22"]));
      expect(upcoming.where((e) => (e as Map)["k"] == "reminder"), isEmpty);
    });

    test("holidays and the last day go as dates, not as countdowns", () {
      expect((snapshot["holidays"]! as List).single, {
        "t": "Allerheiligenferien",
        "from": "2026-10-31",
        "to": "2026-11-08"
      });
      expect(snapshot["lastSchoolDay"], "2027-06-16");
    });

    test("without grades or absences loaded, those parts are empty", () {
      expect(snapshot["grades"], isNull);
      expect(snapshot["absences"], isNull);
    });
  });

  group("remote config", () {
    const source = '''
{
  "calendarRevision": 5,
  "schoolCalendars": {
    "2027": {
      "firstDay": "2027-09-06",
      "lastDay": "2028-06-16",
      "holidays": [
        { "name": "Allerheiligen", "start": "2027-10-30", "end": "2027-11-07" },
        { "name": "kaputt" }
      ]
    },
    "kein Jahr": {}
  },
  "notices": [
    { "id": "a", "text": "Für alle" },
    { "id": "b", "text": "Nur alte Versionen", "belowVersion": "8.0.0" },
    { "id": "c", "text": "Vorbei", "until": "2026-10-01" },
    { "id": "d", "text": "Nur Windows", "platforms": ["windows"] },
    { "text": "ohne id" }
  ]
}''';

    test("reads calendars and leaves out what is broken", () {
      final config = RemoteConfig.parse(source)!;
      expect(config.calendarRevision, 5);
      final calendar = config.schoolCalendars[2027]!;
      expect(calendar.firstDay, UtcDateTime(2027, 9, 6));
      expect(calendar.holidays.single.name, "Allerheiligen");
      expect(config.schoolCalendars, hasLength(1));
      expect(config.notices.map((n) => n.id), ["a", "b", "c", "d"]);
    });

    test("a broken file is no config at all", () {
      expect(RemoteConfig.parse("{nicht json"), isNull);
      expect(RemoteConfig.parse("[]"), isNull);
    });

    test("notices know whom they are for", () {
      final notices = RemoteConfig.parse(source)!.notices;
      bool shows(String id, {String platform = "android"}) =>
          notices.firstWhere((n) => n.id == id).appliesTo(
                platform: platform,
                version: AppVersion.tryParse("8.8.0"),
                today: _today,
              );
      expect(shows("a"), isTrue);
      expect(shows("b"), isFalse);
      expect(shows("c"), isFalse);
      expect(shows("d"), isFalse);
      expect(shows("d", platform: "windows"), isTrue);
    });

    test("its calendar replaces the built-in one, and its revision counts", () {
      addTearDown(() => RemoteConfig.current = null);
      expect(officialSchoolCalendar(2027), isNull);
      RemoteConfig.current = RemoteConfig.parse(source);
      expect(officialSchoolCalendar(2027)!.lastDay, UtcDateTime(2028, 6, 16));
      expect(schoolCalendarRevision, 5);
    });

    test("the file in the repository is valid", () async {
      final file = await _readRepoFile("remote/config.json");
      final config = RemoteConfig.parse(file)!;
      expect(config.calendarRevision,
          greaterThanOrEqualTo(builtInSchoolCalendarRevision));
      // It must agree with the calendar built into the app.
      final remote = config.schoolCalendars[2026]!;
      RemoteConfig.current = null;
      final builtIn = officialSchoolCalendar(2026)!;
      expect(remote.lastDay, builtIn.lastDay);
      expect(remote.holidays.map((h) => [h.name, h.start, h.end]),
          builtIn.holidays.map((h) => [h.name, h.start, h.end]));
    });
  });

  test("Windows updates run the installer without its wizard", () {
    expect(
        UpdateService.silentSetupArguments,
        containsAll(
            ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/CLOSEAPPLICATIONS"]));
  });
}

/// Tests run with the package root as working directory.
Future<String> _readRepoFile(String path) => File(path).readAsString();
