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
import 'package:dr/api/message_compose_api.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/school_time.dart';
import 'package:dr/ui/current_lesson.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';

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

void main() {
  // 1st lesson 07:45, 2nd 08:35, 3rd 09:40.
  final times = [_time(1, 465), _time(2, 515), _time(3, 580)];
  final day = UtcDateTime(2026, 10, 27);

  group("school time (#21, #26)", () {
    test("is Central European time, with summer time", () {
      // 27 October: winter time, UTC+1.
      expect(schoolNow(DateTime.utc(2026, 10, 27, 7, 0)),
          UtcDateTime(2026, 10, 27, 8, 0));
      // 1 June: summer time, UTC+2.
      expect(schoolNow(DateTime.utc(2027, 6, 1, 7, 0)),
          UtcDateTime(2027, 6, 1, 9, 0));
      // The switch: last Sunday of October 2026 is the 25th, 01:00 UTC.
      expect(isEuSummerTime(DateTime.utc(2026, 10, 25, 0, 59)), isTrue);
      expect(isEuSummerTime(DateTime.utc(2026, 10, 25, 1, 0)), isFalse);
    });

    test("a lesson is over once its last hour has ended", () {
      final first = _hour(1, 1, "Deutsch");
      expect(lessonIsOver(day, first, times, UtcDateTime(2026, 10, 27, 8, 34)),
          isFalse);
      expect(lessonIsOver(day, first, times, UtcDateTime(2026, 10, 27, 8, 35)),
          isTrue);
      // A lesson of yesterday is over even without known times.
      expect(
        lessonIsOver(UtcDateTime(2026, 10, 26), _hour(9, 9, "X"), const [],
            UtcDateTime(2026, 10, 27, 7)),
        isTrue,
      );
    });

    test("a double lesson counts down to the end of both", () {
      final calendar = CalendarState((b) => b
        ..days = MapBuilder({
          day: CalendarDay((b) => b
            ..date = day
            ..hours = ListBuilder([
              _hour(1, 1, "Mathematik"),
              _hour(2, 2, "Mathematik"),
              _hour(3, 3, "Englisch"),
            ])),
        }));
      final lesson =
          currentLesson(calendar, times, UtcDateTime(2026, 10, 27, 8, 0))!;
      expect(lesson.subject, "Mathematik");
      expect(lesson.toHour, 2);
      expect(lesson.end, UtcDateTime(2026, 10, 27, 9, 25));
      // In the break between 2nd and 3rd lesson: nothing.
      expect(currentLesson(calendar, times, UtcDateTime(2026, 10, 27, 9, 30)),
          isNull);
      expect(
          CurrentLessonChip.countdown(const Duration(minutes: 3, seconds: 5)),
          "3:05");
      expect(CurrentLessonChip.countdown(const Duration(hours: 1, minutes: 2)),
          "1:02:00");
    });
  });

  testWidgets("message text keeps its line breaks when copied (#20)",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuillDeltaViewer(
          delta: Delta.fromJson([
            {"insert": "Liebe Klasse,\n\nmorgen bitte mitbringen:\nBuch"},
            {
              "insert": "\n",
              "attributes": {"list": "bullet"}
            },
            {"insert": "Hefte"},
            {
              "insert": "\n",
              "attributes": {"list": "bullet"}
            },
          ]),
        ),
      ),
    ));
    final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(texts, hasLength(1));
    expect(
      texts.single.text.toPlainText(),
      "Liebe Klasse,\n\nmorgen bitte mitbringen:\n•  Buch\n•  Hefte",
    );
  });

  test("a reply quotes the message below, in italics (#24)", () {
    final ops = messageOps(
      "Danke!",
      quoteTitle: "Antwort auf die Mitteilung:",
      quote: [
        {"insert": "Wir treffen uns um 8.\n"},
      ],
    );
    expect(ops.first, {"insert": "Danke!\n"});
    expect(ops[1], {"insert": "\n"});
    expect(ops[2]["insert"], "Antwort auf die Mitteilung:");
    expect(ops.skip(2).where((o) => o["attributes"] != null),
        everyElement(containsPair("attributes", containsPair("italic", true))));
    expect(messageOps("Nur Text"), [
      {"insert": "Nur Text\n"}
    ]);
    const forwarded = MessageAttachmentDraft.forwarded(
        sourceMessageId: 5, sourceSubmissionId: 9, name: "a.pdf");
    expect(forwarded.toJson(),
        {"kind": "forwarded", "sourceMessageId": 5, "sourceSubmissionId": 9});
    expect(
      const MessageAttachmentDraft.uploaded(submissionId: 3, name: "b")
          .toJson(),
      {"kind": "temporary", "submissionId": 3},
    );
  });

  test("the start page defaults to the homework (#22)", () {
    expect(SettingsState().startPage, startPageDashboard);
    expect(startPages.keys, contains("calendar"));
  });
}
