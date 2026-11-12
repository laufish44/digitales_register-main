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

import 'package:dr/reducer/calendar.dart';
import 'package:dr/school_year.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lesson(String date, int hour, String subject,
        {bool exam = false}) =>
    <String, dynamic>{
      "isLesson": 1,
      "hour": hour,
      "lesson": <String, dynamic>{
        "date": date,
        "hour": hour,
        "toHour": hour,
        "timeStartObject": <String, dynamic>{"h": "07", "m": "45"},
        "timeEndObject": <String, dynamic>{"h": "08", "m": "35"},
        "rooms": <dynamic>[],
        "teachers": <dynamic>[],
        "subject": <String, dynamic>{"name": subject},
        "homeworkExams": exam
            ? <dynamic>[
                <String, dynamic>{
                  "id": 1,
                  "name": "Test",
                  "homework": 0,
                  "online": 0,
                  "deadline": "$date 07:45:00",
                  "hasGrades": false,
                  "hasGradeGroupSubmissions": false,
                  "typeId": 2,
                  "typeName": "Test",
                }
              ]
            : <dynamic>[],
        "lessonContents": <dynamic>[],
      },
    };

Map<String, dynamic> _day(String date, List<String> subjects) =>
    <String, dynamic>{
      "1": <String, dynamic>{
        "1": <String, dynamic>{
          for (var i = 0; i < subjects.length; i++)
            "${i + 1}": _lesson(date, i + 1, subjects[i], exam: i == 0),
        },
      },
    };

void main() {
  test("the Saturday 28 November gets Friday's lessons, up to the 5th", () {
    final state = parseCalendarResponse(<String, dynamic>{
      "2026-11-26": _day("2026-11-26", ["Deutsch"]),
      "2026-11-27":
          _day("2026-11-27", ["Mathe", "Deutsch", "Ita", "Eng", "BWL", "Sport"]),
    });
    final saturday = state.days[UtcDateTime(2026, 11, 28)]!;
    expect(saturday.hours.map((h) => h.subject),
        ["Mathe", "Deutsch", "Ita", "Eng", "BWL"]);
    expect(saturday.derivedFrom, "Stundenplan vom Freitag, 1.–5. Stunde");
    // Friday's test stays on Friday.
    expect(saturday.hours.first.homeworkExams, isEmpty);
    expect(saturday.hours.first.timeSpans.first.from.day, 28);
    expect(extraSchoolDay(UtcDateTime(2026, 11, 28))!.lastHour, 5);
  });

  test("lessons the register enters for the Saturday win", () {
    final state = parseCalendarResponse(<String, dynamic>{
      "2026-11-27": _day("2026-11-27", ["Mathe", "Deutsch"]),
      "2026-11-28": _day("2026-11-28", ["Religion"]),
    });
    final saturday = state.days[UtcDateTime(2026, 11, 28)]!;
    expect(saturday.hours.map((h) => h.subject), ["Religion"]);
    expect(saturday.derivedFrom, isNull);
  });

  test("other weeks are left alone", () {
    final state = parseCalendarResponse(<String, dynamic>{
      "2026-11-20": _day("2026-11-20", ["Mathe"]),
    });
    expect(state.days[UtcDateTime(2026, 11, 21)], isNull);
  });
}
