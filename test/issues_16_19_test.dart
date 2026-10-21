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
import 'package:dr/stats.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/feedback_dialog.dart';
import 'package:dr/ui/link_text.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GradeAll _grade(int grade) => GradeAll(
      (b) => b
        ..grade = grade
        ..weightPercentage = 100
        ..cancelled = false
        ..type = "Test"
        ..date = UtcDateTime(2026, 10, 1),
    );

void main() {
  group("Ctrl+Enter saves (#16)", () {
    testWidgets("from a text field with several lines", (tester) async {
      var saved = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubmitShortcut(
            onSubmit: () => saved++,
            child: const TextField(maxLines: null, autofocus: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(saved, 1);

      // A plain Enter is a new line, not "save".
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(saved, 1);
    });

    testWidgets("does nothing while saving is not possible", (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SubmitShortcut(
            onSubmit: null,
            child: TextField(autofocus: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Nothing to assert beyond "no exception".
    });
  });

  group("links in reminders (#17)", () {
    test("finds bare addresses and leaves the punctuation after them", () {
      expect(splitLinks("Folien: https://x.it/a?b=1. Danke"), const [
        TextPiece("Folien: "),
        TextPiece("https://x.it/a?b=1", "https://x.it/a?b=1"),
        TextPiece(". Danke"),
      ]);
    });

    test("www. gets https", () {
      expect(splitLinks("siehe www.schule.it"), const [
        TextPiece("siehe "),
        TextPiece("www.schule.it", "https://www.schule.it"),
      ]);
    });

    test("markdown links show their text", () {
      expect(splitLinks("[Moodle](https://moodle.it/kurs) lesen"), const [
        TextPiece("Moodle", "https://moodle.it/kurs"),
        TextPiece(" lesen"),
      ]);
    });

    test("text without links stays one piece", () {
      expect(splitLinks("Kapitel 3 lernen"),
          const [TextPiece("Kapitel 3 lernen")]);
    });
  });

  group("another login ends the session (#18)", () {
    test("the register's 401 is recognised", () {
      expect(
        Wrapper.isSessionTakenOver(
            401, {"forceLogout": true, "noSession": true}),
        isTrue,
      );
      expect(
        Wrapper.isSessionTakenOver(
            401, '{"forceLogout":true,"noSession":true}'),
        isTrue,
      );
    });

    test("other errors are not", () {
      expect(Wrapper.isSessionTakenOver(500, {"forceLogout": true}), isFalse);
      expect(Wrapper.isSessionTakenOver(401, "<html>"), isFalse);
      expect(Wrapper.isSessionTakenOver(null, null), isFalse);
    });
  });

  group("suggestions as GitHub issues", () {
    test("the link fills in title, text, label and version", () {
      final url = feedbackIssueUrl(
        kind: FeedbackKind.idea,
        title: "  Dunkles Widget ",
        text: "Bitte & danke",
        version: "8.8.0",
        platform: "Android",
        repository: "https://github.com/a/b",
      );
      expect(url.path, "/a/b/issues/new");
      expect(url.queryParameters["title"], "Dunkles Widget");
      expect(url.queryParameters["labels"], "enhancement");
      expect(url.queryParameters["body"],
          "Bitte & danke\n\n---\nApp-Version 8.8.0 · Android");
    });

    test("a very long text is cut so the link still works", () {
      final url = feedbackIssueUrl(
        kind: FeedbackKind.bug,
        title: "x",
        text: "a" * 20000,
        version: "1",
        platform: "Windows",
      );
      expect(url.queryParameters["body"]!.length, lessThan(6200));
      expect(url.queryParameters["labels"], "bug");
    });
  });

  group("nothing below a 4", () {
    test("a plan never asks for less than a 4", () {
      // Average 8 from two grades, target 6 with three more grades: the rest
      // could be anything, but no grade is lower than a 4.
      final plan = GradeStats.planForTarget(
          grades: [_grade(800), _grade(800)], target: 600, count: 3)!;
      expect(plan.grades.every((g) => g >= lowestGrade), isTrue);
    });

    test("needing a 4 or less means the target is safe", () {
      final plan = GradeStats.planForTarget(
          grades: [_grade(600), _grade(600)], target: 560, count: 1)!;
      // (5.6 * 3 - 12) / 1 = 4.8 is still needed …
      expect(plan.alreadySafe, isFalse);
      final easy = GradeStats.planForTarget(
          grades: [_grade(600), _grade(600)], target: 530, count: 1)!;
      // … (5.3 * 3 - 12) = 3.9 is below the lowest grade there is.
      expect(easy.alreadySafe, isTrue);
    });
  });
}
