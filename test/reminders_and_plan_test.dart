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
import 'package:dr/reminder_links.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

Homework _entry(int id, HomeworkType type, {String subtitle = ""}) => Homework(
      (b) => b
        ..id = id
        ..type = type
        ..title = type == HomeworkType.homework ? "Erinnerung" : "Test"
        ..subtitle = subtitle
        ..deleted = false
        ..isNew = false
        ..isChanged = false
        ..warning = false
        ..checkable = true
        ..checked = false
        ..deleteable = type == HomeworkType.homework
        ..firstSeen = UtcDateTime(2026, 10, 19),
    );

GradeAll _grade(int grade) => GradeAll(
      (b) => b
        ..grade = grade
        ..weightPercentage = 100
        ..cancelled = false
        ..type = "Test"
        ..date = UtcDateTime(2026, 10, 1),
    );

void main() {
  group("linked reminders (#10)", () {
    final exam = _entry(4711, HomeworkType.gradeGroup);
    final homework = _entry(4711, HomeworkType.lessonHomework);

    test("the tag names the kind of entry and its id", () {
      final text = linkedReminderText("  Kapitel 3 lernen ", exam);
      expect(text, "Kapitel 3 lernen [#t4711]");
      expect(linkKeyIn(text), "t4711");
      expect(reminderTextOf(text), "Kapitel 3 lernen");
      expect(linkKeyIn("Kapitel 3 lernen"), isNull);
      expect(reminderTextOf("Kapitel 3 lernen"), "Kapitel 3 lernen");
    });

    test("a reminder goes with its entry, not with one of another kind", () {
      final note = _entry(1, HomeworkType.homework,
          subtitle: linkedReminderText("Taschenrechner", exam));
      final plain = _entry(2, HomeworkType.homework, subtitle: "Turnsachen");
      final links = DayReminderLinks.of([homework, exam, note, plain]);
      expect(links.remindersOf(exam), [note]);
      expect(links.remindersOf(homework), isEmpty);
      expect(links.isLinked(note), isTrue);
      expect(links.isLinked(plain), isFalse);
    });

    test("a reminder whose entry is not on the day stands on its own", () {
      final orphan = _entry(3, HomeworkType.homework,
          subtitle: linkedReminderText("weg", exam));
      final links = DayReminderLinks.of([homework, orphan]);
      expect(links.isLinked(orphan), isFalse);
    });
  });

  group("what the next grades need (#12)", () {
    // Average 6 from two grades; target 8.
    final grades = [_grade(500), _grade(700)];

    test("one grade would have to be a 12, so it takes more", () {
      final one =
          GradeStats.planForTarget(grades: grades, target: 800, count: 1)!;
      expect(one.average, 1200);
      expect(one.reachable, isFalse);

      final auto = GradeStats.planForTarget(grades: grades, target: 800)!;
      expect(auto.count, 2);
      expect(auto.average, 1000);
      expect(auto.grades, [1000, 1000]);
    });

    test("a fixed number gives an average and a combination", () {
      final three =
          GradeStats.planForTarget(grades: grades, target: 800, count: 3)!;
      // (8 * 5 - 12) / 3 = 9.33…
      expect(three.average, closeTo(933.33, 0.01));
      expect(three.grades, [1000, 1000, 800]);
      expect(three.grades.reduce((a, b) => a + b) / 3,
          greaterThanOrEqualTo(three.average));
    });

    test("says when the target is safe anyway", () {
      final plan =
          GradeStats.planForTarget(grades: grades, target: 400, count: 1)!;
      expect(plan.alreadySafe, isTrue);
    });

    test("says when even the most grades are not enough", () {
      final plan = GradeStats.planForTarget(
          grades: List.filled(20, _grade(300)), target: 900)!;
      expect(plan.count, 8);
      expect(plan.reachable, isFalse);
    });
  });
}
