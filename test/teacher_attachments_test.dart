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

import 'package:dr/data.dart';
import 'package:dr/reducer/calendar.dart';
import 'package:dr/reducer/dashboard.dart';
import 'package:dr/reducer/notifications.dart';
import 'package:dr/search.dart';
import 'package:dr/ui/teacher_attachment.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';

// As the register sends it (shortened from a real test, 13.11.2026).
const _text = <String, dynamic>{
  "id": 81,
  "userId": 344,
  "gradeGroupId": 29,
  "timestamp": "2026-11-09 20:01:17",
  "title": "Was ist auf die Schularbeit zu lernen",
  "type": "text",
  "link": null,
  "file": null,
  "originalName": null,
  "text": '{"ops":[{"insert":"Kurvendiskussion Wiederholung\\n'
      'Theoriefragen (siehe www.example.org)\\n"}]}',
  "deleted": 0,
  "sortorder": 0,
  "typeName": "Text",
  "isDownloadable": true,
};

const _link = <String, dynamic>{
  "id": 82,
  "userId": 344,
  "gradeGroupId": 29,
  "timestamp": "2026-11-09 20:02:00",
  "title": "Übungsblatt",
  "type": "link",
  "link": "https://example.org/blatt",
  "file": null,
  "originalName": null,
  "text": null,
  "typeName": "Link",
};

const _file = <String, dynamic>{
  "id": 83,
  "userId": 344,
  "gradeGroupId": 29,
  "timestamp": "2026-11-09 20:03:00",
  "title": null,
  "type": "file",
  "link": null,
  "file": "abc123",
  "originalName": "Angabe.pdf",
  "text": null,
  "typeName": "Datei",
};

Map<String, dynamic> _calendarWith(List<Map<String, dynamic>> submissions) {
  Map<String, dynamic> time(String h, String m) =>
      <String, dynamic>{"h": h, "m": m};
  return <String, dynamic>{
    "2026-11-13": <String, dynamic>{
      "1": <String, dynamic>{
        "1": <String, dynamic>{
          "1": <String, dynamic>{
            "isLesson": 1,
            "hour": 1,
            "lesson": <String, dynamic>{
              "date": "2026-11-13",
              "hour": 1,
              "toHour": 2,
              "timeStartObject": time("07", "45"),
              "timeEndObject": time("09", "25"),
              "rooms": <dynamic>[],
              "teachers": <dynamic>[],
              "subject": <String, dynamic>{"name": "Mathematik"},
              "homeworkExams": <dynamic>[
                <String, dynamic>{
                  "id": 29,
                  "name": "1. Schularbeit",
                  "homework": 0,
                  "online": 0,
                  "deadline": "2026-11-13 07:45:00",
                  "hasGrades": false,
                  "hasGradeGroupSubmissions": true,
                  "typeId": 2,
                  "typeName": "Schularbeit",
                  "gradeGroupSubmissions": submissions,
                }
              ],
              "lessonContents": <dynamic>[
                <String, dynamic>{
                  "name": "Wiederholung",
                  "typeName": "Fachunterricht",
                  "lessonContentSubmissions": <dynamic>[
                    <String, dynamic>{
                      "id": "5",
                      "lessonContentId": "7",
                      "type": "link",
                      "title": "Video",
                      "link": "https://example.org/video",
                    }
                  ],
                }
              ],
            },
          },
        },
      },
    },
  };
}

SearchResult _entry(String title, UtcDateTime date, {int score = 500}) =>
    SearchResult(
      category: SearchCategory.entry,
      title: title,
      subtitle: "",
      score: score,
      date: date,
    );

Notification _notification(int id, UtcDateTime sent) => Notification((b) => b
  ..id = id
  ..title = "N$id"
  ..timeSent = sent);

void main() {
  group("attachments a teacher adds to a test", () {
    test("texts and links are kept, not dropped as broken files", () {
      final text = parseGradeGroupSubmission(_text)!;
      expect(text.isFile, isFalse);
      expect(text.type, "text");
      expect(text.title, "Was ist auf die Schularbeit zu lernen");
      expect(teacherAttachmentText(text.text),
          "Kurvendiskussion Wiederholung\nTheoriefragen (siehe www.example.org)");

      final link = parseGradeGroupSubmission(_link)!;
      expect(link.isFile, isFalse);
      expect(link.link, "https://example.org/blatt");

      final file = parseGradeGroupSubmission(_file)!;
      expect(file.isFile, isTrue);
      expect(file.originalName, "Angabe.pdf");
    });

    test("an attachment saved by an older version still counts as a file", () {
      final old =
          parseGradeGroupSubmission(_file)!.rebuild((b) => b..type = null);
      expect(old.isFile, isTrue);
    });

    test("plain text that is not a delta is shown as it is", () {
      expect(teacherAttachmentText("Seite 12-14"), "Seite 12-14");
      expect(teacherAttachmentText(null), "");
    });

    test("the calendar keeps them for the test and the lesson", () {
      final state = parseCalendarResponse(_calendarWith([_text, _link, _file]));
      final hour = state.days[UtcDateTime(2026, 11, 13)]!.hours.single;
      final exam = hour.homeworkExams.single;
      expect(exam.submissions!.map((s) => s.type), ["text", "link", "file"]);
      final lesson = hour.lessonContents.single.submissions.single;
      expect(lesson.isFile, isFalse);
      expect(lesson.link, "https://example.org/video");
    });

    testWidgets("a text attachment shows its title and text", (tester) async {
      final text = parseGradeGroupSubmission(_text)!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TeacherAttachment(
            type: text.type,
            title: text.title,
            text: text.text,
            link: text.link,
          ),
        ),
      ));
      expect(
          find.text("Was ist auf die Schularbeit zu lernen"), findsOneWidget);
      expect(find.textContaining("Kurvendiskussion", findRichText: true),
          findsOneWidget);
    });
  });

  group("search lists tests and homework by date (#28)", () {
    test("the next one first, past ones at the end", () {
      final today = UtcDateTime(2026, 11, 10);
      final results = [
        _entry("April", UtcDateTime(2027, 4, 30), score: 800),
        _entry("Januar", UtcDateTime(2027, 1, 8)),
        _entry("Oktober", UtcDateTime(2026, 10, 1)),
        _entry("Dezember", UtcDateTime(2026, 12, 4), score: 100),
        _entry("November", UtcDateTime(2026, 11, 3)),
      ];
      Search.entriesByDate(results, today: today);
      expect(results.map((r) => r.title),
          ["Dezember", "Januar", "April", "November", "Oktober"]);
    });

    test("other kinds keep their places", () {
      final results = [
        _entry("B", UtcDateTime(2026, 12, 2)),
        const SearchResult(
            category: SearchCategory.subject,
            title: "Fach",
            subtitle: "",
            score: 700),
        _entry("A", UtcDateTime(2026, 12, 1)),
      ];
      Search.entriesByDate(results, today: UtcDateTime(2026, 11, 10));
      expect(results.map((r) => r.title), ["A", "Fach", "B"]);
    });
  });

  group("notification history (#27)", () {
    test("keeps read notifications, newest first, no duplicates", () {
      final history = [
        _notification(1, UtcDateTime(2026, 11, 1)),
        _notification(2, UtcDateTime(2026, 11, 2)),
      ];
      final merged = mergeNotificationHistory(history, [
        _notification(2, UtcDateTime(2026, 11, 2)),
        _notification(3, UtcDateTime(2026, 11, 3)),
      ]);
      expect(merged.map((n) => n.id), [3, 2, 1]);
    });

    test("does not grow without end", () {
      final many = [
        for (var i = 0; i < notificationHistoryLength + 20; i++)
          _notification(i, UtcDateTime(2026, 1, 1).add(Duration(hours: i))),
      ];
      final merged = mergeNotificationHistory(const [], many);
      expect(merged.length, notificationHistoryLength);
      expect(merged.first.id, notificationHistoryLength + 19);
    });
  });
}
