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

/// Pure calculations on top of the data the register already gives us:
/// grade trends, absence budgets and upcoming exams.
///
/// Everything here is deliberately free of Flutter and of the redux store so
/// that it can be unit tested. Grades are integers scaled by 100 throughout the
/// app (850 means 8.5), and that convention is kept here.
library;

import 'dart:math' as math;

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';

/// A grade that actually counts towards an average.
bool countsTowardsAverage(GradeAll grade) =>
    !grade.cancelled && grade.grade != null && grade.weightPercentage > 0;

class GradeStats {
  GradeStats._();

  /// The weighted average of [grades], scaled by 100, or null if nothing counts.
  static double? weightedAverage(Iterable<GradeAll> grades) {
    var sum = 0, weight = 0;
    for (final grade in grades.where(countsTowardsAverage)) {
      sum += grade.grade! * grade.weightPercentage;
      weight += grade.weightPercentage;
    }
    if (weight == 0) return null;
    return sum / weight;
  }

  /// The average per grade type ("Schularbeit", "Test", ...), scaled by 100.
  static Map<String, double> averageByType(Iterable<GradeAll> grades) {
    final byType = <String, List<GradeAll>>{};
    for (final grade in grades.where(countsTowardsAverage)) {
      byType.putIfAbsent(grade.type, () => []).add(grade);
    }
    return {
      for (final entry in byType.entries)
        if (weightedAverage(entry.value) != null)
          entry.key: weightedAverage(entry.value)!,
    };
  }

  /// How the average developed: one point per grade, in chronological order,
  /// each holding the average of everything up to and including that grade.
  ///
  /// This is what makes a trend visible — a single average hides whether things
  /// are getting better or worse.
  static List<AveragePoint> runningAverage(Iterable<GradeAll> grades) {
    final sorted = grades.where(countsTowardsAverage).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final points = <AveragePoint>[];
    var sum = 0, weight = 0;
    for (final grade in sorted) {
      sum += grade.grade! * grade.weightPercentage;
      weight += grade.weightPercentage;
      points.add(AveragePoint(date: grade.date, average: sum / weight));
    }
    return points;
  }

  /// Least squares slope of the grades over time, in grade points per 30 days.
  ///
  /// Positive means improving. Null if there are fewer than two grades or they
  /// all fall on the same day (no slope is defined then).
  static double? trendPerMonth(Iterable<GradeAll> grades) {
    final sorted = grades.where(countsTowardsAverage).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.length < 2) return null;

    final firstDay = sorted.first.date.millisecondsSinceEpoch / 86400000.0;
    var sumX = 0.0, sumY = 0.0, sumXy = 0.0, sumXx = 0.0, n = 0.0;
    for (final grade in sorted) {
      final x = grade.date.millisecondsSinceEpoch / 86400000.0 - firstDay;
      final y = grade.grade! / 100.0;
      final w = grade.weightPercentage.toDouble();
      sumX += w * x;
      sumY += w * y;
      sumXy += w * x * y;
      sumXx += w * x * x;
      n += w;
    }
    final denominator = n * sumXx - sumX * sumX;
    if (denominator.abs() < 1e-9) return null;
    return (n * sumXy - sumX * sumY) / denominator * 30;
  }

  /// The grade needed on the next assessment to reach [target].
  ///
  /// [target] and the result are scaled by 100, [newWeightPercentage] is the
  /// weight the upcoming grade will have. Returns null if the existing grades
  /// carry no weight. The result may be outside 1..10, which is exactly the
  /// useful answer: it means the target is out of reach (or already secured).
  static double? requiredGradeForTarget({
    required Iterable<GradeAll> grades,
    required double target,
    int newWeightPercentage = 100,
  }) {
    if (newWeightPercentage <= 0) return null;
    var sum = 0, weight = 0;
    for (final grade in grades.where(countsTowardsAverage)) {
      sum += grade.grade! * grade.weightPercentage;
      weight += grade.weightPercentage;
    }
    if (weight == 0) return null;
    final total = weight + newWeightPercentage;
    return (target * total - sum) / newWeightPercentage;
  }

  /// The average if the next grade were [grade] with [newWeightPercentage].
  static double? averageWith({
    required Iterable<GradeAll> grades,
    required double grade,
    int newWeightPercentage = 100,
  }) {
    var sum = 0, weight = 0;
    for (final g in grades.where(countsTowardsAverage)) {
      sum += g.grade! * g.weightPercentage;
      weight += g.weightPercentage;
    }
    final total = weight + newWeightPercentage;
    if (total == 0) return null;
    return (sum + grade * newWeightPercentage) / total;
  }

  /// Best and worst grade, and how far the grades spread.
  static GradeSpread? spread(Iterable<GradeAll> grades) {
    final counting = grades.where(countsTowardsAverage).toList();
    if (counting.isEmpty) return null;
    var best = counting.first.grade!, worst = counting.first.grade!;
    for (final grade in counting) {
      best = math.max(best, grade.grade!);
      worst = math.min(worst, grade.grade!);
    }
    final average = weightedAverage(counting)!;
    var varianceSum = 0.0, weight = 0.0;
    for (final grade in counting) {
      final d = grade.grade! - average;
      varianceSum += d * d * grade.weightPercentage;
      weight += grade.weightPercentage;
    }
    return GradeSpread(
      best: best.toDouble(),
      worst: worst.toDouble(),
      average: average,
      standardDeviation: weight == 0 ? 0 : math.sqrt(varianceSum / weight),
    );
  }

  /// Compares the first half of the grades with the second half.
  ///
  /// Returns the difference (second minus first) in grade points, or null when
  /// there are too few grades for the comparison to say anything.
  static double? improvement(Iterable<GradeAll> grades) {
    final sorted = grades.where(countsTowardsAverage).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.length < 4) return null;
    final half = sorted.length ~/ 2;
    final first = weightedAverage(sorted.take(half));
    final second = weightedAverage(sorted.skip(half));
    if (first == null || second == null) return null;
    return (second - first) / 100;
  }
}

class AveragePoint {
  const AveragePoint({required this.date, required this.average});

  final UtcDateTime date;

  /// Scaled by 100, like everywhere else in the app.
  final double average;
}

class GradeSpread {
  const GradeSpread({
    required this.best,
    required this.worst,
    required this.average,
    required this.standardDeviation,
  });

  /// All scaled by 100.
  final double best, worst, average, standardDeviation;
}

class AbsenceStats {
  AbsenceStats._();

  /// The share of missed lessons the register reports, as a percentage.
  ///
  /// The server sends this as a string (e.g. "12,5" or "12.5"), so it is parsed
  /// leniently. Returns null when it is missing or unparseable.
  static double? missedPercentage(AbsenceStatistic? statistic) {
    final raw = statistic?.percentage;
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(",", ".").replaceAll("%", "").trim());
  }

  /// Whether the student should be warned about their absence rate.
  static bool shouldWarn({
    required AbsenceStatistic? statistic,
    required double thresholdPercentage,
  }) {
    final percentage = missedPercentage(statistic);
    if (percentage == null) return false;
    return percentage >= thresholdPercentage;
  }

  /// The number of absences that are still waiting for a justification.
  static int notYetJustifiedCount(Iterable<AbsenceGroup> absences) => absences
      .where((a) => a.justified == AbsenceJustified.notYetJustified)
      .length;

  /// A full lesson is 50 minutes; late arrivals and early leaves are counted in
  /// minutes and add up to further hours.
  static const minutesPerLesson = 50;

  /// How many lessons were missed in total, late arrivals included.
  static double missedLessons(Iterable<AbsenceGroup> absences) {
    var total = 0.0;
    for (final group in absences) {
      for (final absence in group.absences) {
        total += absence.minutes == minutesPerLesson
            ? 1
            : (absence.minutesCameTooLate + absence.minutesLeftTooEarly) /
                minutesPerLesson;
      }
    }
    return total;
  }

  /// How many lessons there are in the year, worked back from the percentage.
  ///
  /// The register reports the share of missed lessons but never the total, so
  /// the total is inferred: if 12 lessons are 2.5 %, the year has 480. That is
  /// exact when the server rounds the percentage generously and a good estimate
  /// otherwise — good enough to answer "how much more can I miss".
  static double? estimatedTotalLessons({
    required AbsenceStatistic? statistic,
    required Iterable<AbsenceGroup> absences,
  }) {
    final percentage = missedPercentage(statistic);
    if (percentage == null || percentage <= 0) return null;
    final missed = missedLessons(absences);
    if (missed <= 0) return null;
    return missed / (percentage / 100);
  }

  /// What is left of the allowance before [limitPercentage] is reached.
  static AbsenceBudget? budget({
    required AbsenceStatistic? statistic,
    required Iterable<AbsenceGroup> absences,
    required double limitPercentage,
  }) {
    final total =
        estimatedTotalLessons(statistic: statistic, absences: absences);
    if (total == null) return null;
    final missed = missedLessons(absences);
    final allowed = total * limitPercentage / 100;
    return AbsenceBudget(
      missedLessons: missed,
      estimatedTotalLessons: total,
      allowedLessons: allowed,
      limitPercentage: limitPercentage,
      percentage: missedPercentage(statistic) ?? 0,
    );
  }

  /// Missed lessons per weekday (`DateTime.monday` … `DateTime.sunday`).
  static Map<int, int> missedByWeekday(Iterable<AbsenceGroup> absences) {
    final result = <int, int>{};
    for (final group in absences) {
      for (final absence in group.absences) {
        result.update(absence.date.weekday, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return result;
  }

  /// Missed lessons per lesson of the day — the 1st, the 2nd and so on.
  ///
  /// This is the answer to "which lesson do I miss most", and the one people
  /// are usually surprised by.
  static Map<int, int> missedByLesson(Iterable<AbsenceGroup> absences) {
    final result = <int, int>{};
    for (final group in absences) {
      for (final absence in group.absences) {
        result.update(absence.hour, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return result;
  }

  /// Missed lessons per calendar month, keyed `yyyy-MM`.
  static Map<String, int> missedByMonth(Iterable<AbsenceGroup> absences) {
    final result = <String, int>{};
    for (final group in absences) {
      for (final absence in group.absences) {
        final key = "${absence.date.year}-"
            "${absence.date.month.toString().padLeft(2, "0")}";
        result.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return result;
  }

  /// Missed lessons per subject.
  ///
  /// Needs the calendar to say which subject a given date and hour was, so the
  /// result only covers the weeks that have been fetched. The second value of
  /// each entry is how many of the missed lessons could not be matched.
  static SubjectAbsences missedBySubject({
    required Iterable<AbsenceGroup> absences,
    required CalendarState calendar,
  }) {
    final subjectOfLesson = <String, String>{};
    for (final day in calendar.days.values) {
      final date = "${day.date.year}-${day.date.month}-${day.date.day}";
      for (final hour in day.hours) {
        for (var h = hour.fromHour; h <= hour.toHour; h++) {
          subjectOfLesson["$date/$h"] = hour.subject;
        }
      }
    }

    final result = <String, int>{};
    var unknown = 0;
    for (final group in absences) {
      for (final absence in group.absences) {
        final key = "${absence.date.year}-${absence.date.month}-"
            "${absence.date.day}/${absence.hour}";
        final subject = subjectOfLesson[key];
        if (subject == null) {
          unknown++;
        } else {
          result.update(subject, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    return SubjectAbsences(bySubject: result, unmatched: unknown);
  }

  /// The share [count] makes up of [total], as a percentage.
  static double share(int count, int total) =>
      total <= 0 ? 0 : count * 100 / total;
}

class AbsenceBudget {
  const AbsenceBudget({
    required this.missedLessons,
    required this.estimatedTotalLessons,
    required this.allowedLessons,
    required this.limitPercentage,
    required this.percentage,
  });

  final double missedLessons;
  final double estimatedTotalLessons;

  /// How many lessons may be missed in total before the limit is reached.
  final double allowedLessons;

  final double limitPercentage;

  /// What the register itself reports, for comparison.
  final double percentage;

  /// How many more lessons are left. Negative once the limit is passed.
  double get remainingLessons => allowedLessons - missedLessons;

  bool get exceeded => remainingLessons < 0;

  /// The same figure spread over [weeks], e.g. "that is 1.5 per week".
  double perWeek(double weeks) => weeks <= 0 ? 0 : remainingLessons / weeks;

  /// The same figure as full school days, given [lessonsPerDay].
  double perDay(double lessonsPerDay) =>
      lessonsPerDay <= 0 ? 0 : remainingLessons / lessonsPerDay;
}

class SubjectAbsences {
  const SubjectAbsences({required this.bySubject, required this.unmatched});

  final Map<String, int> bySubject;

  /// Missed lessons whose subject is unknown because that week of the calendar
  /// has not been loaded.
  final int unmatched;
}

/// How a lesson in the calendar relates to the student's absences.
enum AbsenceMark {
  /// Nothing to show.
  none,

  /// Announced in advance and not yet in the past ("vorentschuldigt").
  announced,

  /// The student was away and the absence is justified.
  justified,

  /// The student was away and it still needs a justification.
  notJustified,
}

class AbsenceMarks {
  AbsenceMarks._();

  /// Whether [date] at lesson [hour] is covered by an announced absence.
  ///
  /// A range spanning several days starts at `startHour` on the first day and
  /// ends at `endHour` on the last one; the days in between are covered
  /// completely.
  static bool isAnnounced(
    FutureAbsence absence, {
    required UtcDateTime date,
    required int hour,
  }) {
    final day = UtcDateTime(date.year, date.month, date.day);
    final start = UtcDateTime(absence.startDate.year, absence.startDate.month,
        absence.startDate.day);
    final end = UtcDateTime(
        absence.endDate.year, absence.endDate.month, absence.endDate.day);
    if (day.isBefore(start) || day.isAfter(end)) return false;

    final isFirst = !day.isAfter(start);
    final isLast = !day.isBefore(end);
    if (isFirst && isLast) {
      return hour >= absence.startHour && hour <= absence.endHour;
    }
    if (isFirst) return hour >= absence.startHour;
    if (isLast) return hour <= absence.endHour;
    return true;
  }

  /// The mark to show for a single lesson.
  ///
  /// Absences that already happened win over announced ones: once the lesson is
  /// in the past, what actually got recorded is the interesting part.
  static AbsenceMark forHour({
    required UtcDateTime date,
    required int hour,
    required Iterable<AbsenceGroup> absences,
    required Iterable<FutureAbsence> futureAbsences,
  }) {
    final day = UtcDateTime(date.year, date.month, date.day);
    for (final group in absences) {
      for (final absence in group.absences) {
        final absenceDay = UtcDateTime(
            absence.date.year, absence.date.month, absence.date.day);
        if (absenceDay == day && absence.hour == hour) {
          return group.justified == AbsenceJustified.notJustified ||
                  group.justified == AbsenceJustified.notYetJustified
              ? AbsenceMark.notJustified
              : AbsenceMark.justified;
        }
      }
    }
    for (final future in futureAbsences) {
      if (isAnnounced(future, date: date, hour: hour)) {
        return AbsenceMark.announced;
      }
    }
    return AbsenceMark.none;
  }

  /// The strongest mark across a lesson block spanning [fromHour]..[toHour].
  static AbsenceMark forRange({
    required UtcDateTime date,
    required int fromHour,
    required int toHour,
    required Iterable<AbsenceGroup> absences,
    required Iterable<FutureAbsence> futureAbsences,
  }) {
    var result = AbsenceMark.none;
    for (var hour = fromHour; hour <= toHour; hour++) {
      final mark = forHour(
        date: date,
        hour: hour,
        absences: absences,
        futureAbsences: futureAbsences,
      );
      if (mark.index > result.index) result = mark;
    }
    return result;
  }
}

class ExamCountdown {
  ExamCountdown._();

  /// The exams still ahead, soonest first.
  ///
  /// Reads the dashboard as well as the calendar, because the two are filled at
  /// different times: the dashboard is fetched on every start, the calendar only
  /// once the calendar page asks for a week. Looking at the calendar alone left
  /// the card empty for anyone who had not opened the calendar in this session —
  /// which is what made "Demnächst" appear broken.
  ///
  /// [within] limits how far to look ahead; entries in the past are dropped.
  static List<UpcomingExam> upcoming(
    CalendarState calendar, {
    required UtcDateTime now,
    DashboardState? dashboard,
    Duration within = const Duration(days: 30),
    bool includeHomework = false,
    bool includeExams = true,
    bool includeDone = false,
  }) {
    final limit = now.add(within);
    // Compare by day: a test at 09:20 today is still "today", and a deadline of
    // 00:00 on the last day of the window must not fall out of it.
    final today = UtcDateTime(now.year, now.month, now.day);
    final lastDay = UtcDateTime(limit.year, limit.month, limit.day);

    final all = Agenda.collect(calendar: calendar, dashboard: dashboard);
    final done = _doneIdentities(all);

    return _sortAndDeduplicate(
      all.where((entry) {
        final due = UtcDateTime(
            entry.deadline.year, entry.deadline.month, entry.deadline.day);
        if (due.isBefore(today) || due.isAfter(lastDay)) return false;
        if (!includeDone && done.contains(entry.identity)) return false;
        return entry.isExam ? includeExams : includeHomework;
      }),
    );
  }

  /// Which entries the user has ticked off.
  ///
  /// Collected by identity rather than per entry: the same homework arrives
  /// from the dashboard (where it carries the tick) and from the calendar
  /// (where it does not), and one tick should remove both.
  static Set<String> _doneIdentities(Iterable<UpcomingExam> entries) => {
        for (final entry in entries)
          if (entry.done) entry.identity,
      };

  static List<UpcomingExam> _sortAndDeduplicate(Iterable<UpcomingExam> input) {
    final entries = input.toList()
      ..sort((a, b) => a.deadline.compareTo(b.deadline));
    // The same entry shows up once per lesson of the day, and again in both the
    // dashboard and the calendar.
    final seen = <String>{};
    return entries.where((e) => seen.add(e.identity)).toList();
  }
}

/// Everything the register has to say about a given day, from both sources.
class Agenda {
  Agenda._();

  /// Every homework and exam entry the app currently knows about.
  ///
  /// Duplicates are possible — [ExamCountdown._sortAndDeduplicate] and
  /// [forDay] remove them.
  static List<UpcomingExam> collect({
    required CalendarState calendar,
    DashboardState? dashboard,
  }) {
    final entries = <UpcomingExam>[];

    for (final day in calendar.days.values) {
      for (final hour in day.hours) {
        for (final exam in hour.homeworkExams) {
          entries.add(
            UpcomingExam(
              name: exam.name,
              subject: hour.subject,
              typeName: exam.typeName,
              deadline: exam.deadline,
              // The register marks plain homework with `homework != 0`;
              // everything else is an assessment of some kind.
              isExam: !exam.homework,
              warning: exam.warning,
              // The calendar does not carry the tick; the dashboard copy of the
              // same entry does.
              done: false,
            ),
          );
        }
      }
    }

    for (final day in dashboard?.allDays ?? const <Day>[]) {
      for (final homework in day.homework) {
        if (homework.deleted) continue;
        // Grades and observations are results, not something that is coming up.
        if (homework.type == HomeworkType.grade ||
            homework.type == HomeworkType.observation) {
          continue;
        }
        // `warning` is the dashboard's own "this is a test" flag (it is set
        // from the same `homework == 0` the calendar uses).
        final isExam =
            homework.warning || homework.type == HomeworkType.gradeGroup;
        entries.add(
          UpcomingExam(
            name: homework.title,
            subject: homework.label ?? "",
            typeName: homework.subtitle,
            deadline: day.date,
            isExam: isExam,
            warning: homework.warning,
            done: homework.checkable && homework.checked,
          ),
        );
      }
    }

    return entries;
  }

  /// The entries due on [day], deduplicated and sorted.
  static List<UpcomingExam> forDay({
    required CalendarState calendar,
    DashboardState? dashboard,
    required UtcDateTime day,
    bool includeExams = true,
    bool includeHomework = true,
    bool includeDone = false,
  }) {
    final wanted = UtcDateTime(day.year, day.month, day.day);
    final all = collect(calendar: calendar, dashboard: dashboard);
    final done = ExamCountdown._doneIdentities(all);

    return ExamCountdown._sortAndDeduplicate(
      all.where((entry) {
        final due = UtcDateTime(
            entry.deadline.year, entry.deadline.month, entry.deadline.day);
        if (due != wanted) return false;
        if (!includeDone && done.contains(entry.identity)) return false;
        return entry.isExam ? includeExams : includeHomework;
      }),
    );
  }

  /// The lessons of [day], in order. Only the calendar knows these, so the list
  /// is empty until the week has been fetched.
  static List<CalendarHour> lessonsOn(CalendarState calendar, UtcDateTime day) {
    final wanted = UtcDateTime(day.year, day.month, day.day);
    for (final calendarDay in calendar.days.values) {
      final date = UtcDateTime(calendarDay.date.year, calendarDay.date.month,
          calendarDay.date.day);
      if (date == wanted) {
        return calendarDay.hours.toList()
          ..sort((a, b) => a.fromHour.compareTo(b.fromHour));
      }
    }
    return const [];
  }
}

class UpcomingExam {
  const UpcomingExam({
    required this.name,
    required this.subject,
    required this.typeName,
    required this.deadline,
    required this.isExam,
    required this.warning,
    this.done = false,
  });

  final String name, subject, typeName;
  final UtcDateTime deadline;
  final bool isExam, warning;

  /// Ticked off on the dashboard. Such entries drop out of the cards.
  final bool done;

  bool get isHomework => !isExam;

  /// What makes two entries the same thing, seen through two different
  /// endpoints. The time of day is left out on purpose: the dashboard dates an
  /// entry at midnight while the calendar dates it at the lesson.
  String get identity => "${name.trim()}|${subject.trim()}|"
      "${deadline.year}-${deadline.month}-${deadline.day}";

  int daysFrom(UtcDateTime now) {
    final today = UtcDateTime(now.year, now.month, now.day);
    final due = UtcDateTime(deadline.year, deadline.month, deadline.day);
    return due.difference(today).inDays;
  }

  String countdownLabel(UtcDateTime now) {
    final days = daysFrom(now);
    if (days <= 0) return "Heute";
    if (days == 1) return "Morgen";
    if (days < 7) return "In $days Tagen";
    if (days < 14) return "Nächste Woche";
    return "In ${(days / 7).floor()} Wochen";
  }
}
