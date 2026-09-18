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
import 'package:dr/data.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

GradeAll _grade(
  int grade, {
  int weight = 100,
  int day = 1,
  bool cancelled = false,
  String type = "Schularbeit",
}) =>
    GradeAll(
      (b) => b
        ..grade = grade
        ..weightPercentage = weight
        ..cancelled = cancelled
        ..type = type
        ..date = UtcDateTime(2026, 1, day),
    );

Absence _absence(int day, int hour) => Absence(
      (b) => b
        ..minutes = 50
        ..minutesCameTooLate = 0
        ..minutesLeftTooEarly = 0
        ..date = UtcDateTime(2026, 3, day)
        ..hour = hour,
    );

AbsenceGroup _group(
  List<Absence> absences, {
  AbsenceJustified justified = AbsenceJustified.justified,
}) =>
    AbsenceGroup(
      (b) => b
        ..justified = justified
        ..hours = absences.length
        ..minutes = 0
        ..absences = ListBuilder(absences),
    );

FutureAbsence _future({
  required int startDay,
  required int endDay,
  required int startHour,
  required int endHour,
}) =>
    FutureAbsence(
      (b) => b
        ..justified = AbsenceJustified.notYetJustified
        ..startDate = UtcDateTime(2026, 3, startDay)
        ..endDate = UtcDateTime(2026, 3, endDay)
        ..startHour = startHour
        ..endHour = endHour,
    );

void main() {
  group("GradeStats.weightedAverage", () {
    test("weights grades", () {
      // 10 at 100% and 6 at 300% -> (1000 + 1800) / 400 = 700
      expect(
        GradeStats.weightedAverage([_grade(1000), _grade(600, weight: 300)]),
        700,
      );
    });

    test("ignores cancelled grades and zero weights", () {
      expect(
        GradeStats.weightedAverage([
          _grade(1000),
          _grade(100, cancelled: true),
          _grade(100, weight: 0),
        ]),
        1000,
      );
    });

    test("is null without anything that counts", () {
      expect(GradeStats.weightedAverage([_grade(500, cancelled: true)]), isNull);
    });
  });

  group("GradeStats.requiredGradeForTarget", () {
    test("says what the next grade has to be", () {
      // One 6 so far; to average 8 with an equally weighted next grade the
      // next one has to be a 10.
      expect(
        GradeStats.requiredGradeForTarget(
          grades: [_grade(600)],
          target: 800,
        ),
        1000,
      );
    });

    test("returns an unreachable value when the target is out of reach", () {
      final required = GradeStats.requiredGradeForTarget(
        grades: [_grade(400)],
        target: 900,
      );
      expect(required, greaterThan(1000),
          reason: "an impossible target must be visible as such");
    });

    test("accounts for the weight of the upcoming grade", () {
      expect(
        GradeStats.requiredGradeForTarget(
          grades: [_grade(600)],
          target: 800,
          newWeightPercentage: 300,
        ),
        // (800*400 - 600*100) / 300
        closeTo(866.67, 0.01),
      );
    });

    test("is null without previous grades", () {
      expect(
        GradeStats.requiredGradeForTarget(grades: const [], target: 800),
        isNull,
      );
    });
  });

  group("GradeStats.trendPerMonth", () {
    test("is positive when grades improve", () {
      final trend = GradeStats.trendPerMonth([
        _grade(500, day: 1),
        _grade(700, day: 15),
        _grade(900, day: 31),
      ]);
      expect(trend, isNotNull);
      expect(trend!, greaterThan(0));
    });

    test("is negative when grades get worse", () {
      final trend = GradeStats.trendPerMonth([
        _grade(900, day: 1),
        _grade(600, day: 20),
      ]);
      expect(trend!, lessThan(0));
    });

    test("is null with a single grade or a single day", () {
      expect(GradeStats.trendPerMonth([_grade(800)]), isNull);
      expect(
        GradeStats.trendPerMonth([_grade(800, day: 3), _grade(600, day: 3)]),
        isNull,
      );
    });
  });

  test("GradeStats.runningAverage follows the grades chronologically", () {
    final points = GradeStats.runningAverage([
      _grade(1000, day: 5),
      _grade(600, day: 1),
    ]);
    expect(points.length, 2);
    expect(points.first.average, 600, reason: "oldest grade comes first");
    expect(points.last.average, 800);
  });

  test("GradeStats.averageByType splits by type", () {
    final byType = GradeStats.averageByType([
      _grade(1000, type: "Schularbeit"),
      _grade(600, type: "Test"),
      _grade(800, type: "Test"),
    ]);
    expect(byType["Schularbeit"], 1000);
    expect(byType["Test"], 700);
  });

  test("GradeStats.spread reports best, worst and deviation", () {
    final spread = GradeStats.spread([_grade(400), _grade(1000)]);
    expect(spread!.best, 1000);
    expect(spread.worst, 400);
    expect(spread.average, 700);
    expect(spread.standardDeviation, 300);
  });

  test("GradeStats.improvement compares both halves", () {
    final improvement = GradeStats.improvement([
      _grade(500, day: 1),
      _grade(500, day: 2),
      _grade(700, day: 3),
      _grade(700, day: 4),
    ]);
    expect(improvement, 2.0);
  });

  group("AbsenceStats", () {
    test("parses a percentage with a comma", () {
      final statistic = AbsenceStatistic((b) => b..percentage = "12,5");
      expect(AbsenceStats.missedPercentage(statistic), 12.5);
    });

    test("warns at or above the threshold", () {
      final statistic = AbsenceStatistic((b) => b..percentage = "20");
      expect(
        AbsenceStats.shouldWarn(statistic: statistic, thresholdPercentage: 20),
        isTrue,
      );
      expect(
        AbsenceStats.shouldWarn(statistic: statistic, thresholdPercentage: 25),
        isFalse,
      );
    });

    test("does not warn without data", () {
      expect(
        AbsenceStats.shouldWarn(statistic: null, thresholdPercentage: 10),
        isFalse,
      );
    });
  });

  group("AbsenceMarks", () {
    test("marks the hours of a single day range", () {
      final absence =
          _future(startDay: 10, endDay: 10, startHour: 3, endHour: 5);
      final date = UtcDateTime(2026, 3, 10);
      expect(AbsenceMarks.isAnnounced(absence, date: date, hour: 2), isFalse);
      expect(AbsenceMarks.isAnnounced(absence, date: date, hour: 3), isTrue);
      expect(AbsenceMarks.isAnnounced(absence, date: date, hour: 5), isTrue);
      expect(AbsenceMarks.isAnnounced(absence, date: date, hour: 6), isFalse);
    });

    test("covers whole days in the middle of a range", () {
      final absence =
          _future(startDay: 10, endDay: 12, startHour: 4, endHour: 2);
      // First day: only from the 4th lesson on.
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 10), hour: 3),
        isFalse,
      );
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 10), hour: 4),
        isTrue,
      );
      // Middle day: everything.
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 11), hour: 1),
        isTrue,
      );
      // Last day: only up to the 2nd lesson.
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 12), hour: 2),
        isTrue,
      );
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 12), hour: 3),
        isFalse,
      );
    });

    test("ignores days outside the range", () {
      final absence =
          _future(startDay: 10, endDay: 10, startHour: 1, endHour: 8);
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 9), hour: 3),
        isFalse,
      );
      expect(
        AbsenceMarks.isAnnounced(absence,
            date: UtcDateTime(2026, 3, 11), hour: 3),
        isFalse,
      );
    });

    test("a recorded absence wins over an announced one", () {
      final mark = AbsenceMarks.forHour(
        date: UtcDateTime(2026, 3, 10),
        hour: 3,
        absences: [
          _group([_absence(10, 3)],
              justified: AbsenceJustified.notYetJustified)
        ],
        futureAbsences: [
          _future(startDay: 10, endDay: 10, startHour: 1, endHour: 8)
        ],
      );
      expect(mark, AbsenceMark.notJustified);
    });

    test("distinguishes justified from not yet justified", () {
      expect(
        AbsenceMarks.forHour(
          date: UtcDateTime(2026, 3, 10),
          hour: 3,
          absences: [_group([_absence(10, 3)])],
          futureAbsences: const [],
        ),
        AbsenceMark.justified,
      );
    });

    test("reports nothing for an untouched lesson", () {
      expect(
        AbsenceMarks.forHour(
          date: UtcDateTime(2026, 3, 10),
          hour: 7,
          absences: [_group([_absence(10, 3)])],
          futureAbsences: const [],
        ),
        AbsenceMark.none,
      );
    });

    test("forRange picks the most important mark in the block", () {
      final mark = AbsenceMarks.forRange(
        date: UtcDateTime(2026, 3, 10),
        fromHour: 1,
        toHour: 4,
        absences: [
          _group([_absence(10, 4)],
              justified: AbsenceJustified.notYetJustified)
        ],
        futureAbsences: const [],
      );
      expect(mark, AbsenceMark.notJustified);
    });
  });
}
