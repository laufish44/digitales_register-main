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

/// One page with everything the app can work out from the register's data.
library;

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_year.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';

const _weekdayNames = {
  DateTime.monday: "Montag",
  DateTime.tuesday: "Dienstag",
  DateTime.wednesday: "Mittwoch",
  DateTime.thursday: "Donnerstag",
  DateTime.friday: "Freitag",
  DateTime.saturday: "Samstag",
  DateTime.sunday: "Sonntag",
};

const _monthNames = [
  "Jänner",
  "Februar",
  "März",
  "April",
  "Mai",
  "Juni",
  "Juli",
  "August",
  "September",
  "Oktober",
  "November",
  "Dezember",
];

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({
    super.key,
    required this.grades,
    required this.absences,
    required this.calendar,
    required this.dashboard,
    required this.limitPercentage,
    required this.holidays,
    required this.lastSchoolDay,
    required this.lessonTimes,
    required this.loading,
  });

  final GradesState grades;
  final AbsencesState absences;
  final CalendarState calendar;
  final DashboardState dashboard;
  final int limitPercentage;
  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final List<LessonTime> lessonTimes;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Statistik")),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          _GradeStatistics(grades: grades),
          _AbsenceStatistics(
            absences: absences,
            calendar: calendar,
            limitPercentage: limitPercentage,
            lessonTimes: lessonTimes,
          ),
          _EntryStatistics(dashboard: dashboard, calendar: calendar),
          _YearStatistics(
            holidays: holidays,
            lastSchoolDay: lastSchoolDay,
          ),
        ],
      ),
    );
  }
}

/// A heading with a card below it — the page is a stack of these.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.emptyText,
  });

  final String title;
  final List<Widget> children;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children.isEmpty && emptyText != null
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(emptyText!),
                      ),
                    ]
                  : children,
            ),
          ),
        ),
      ],
    );
  }
}

/// Label, value, and a bar showing the share — how the distributions are shown.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.count,
    required this.total,
    this.highlight = false,
  });

  final String label;
  final int count;
  final int total;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = AbsenceStats.share(count, total);
    final color =
        highlight ? theme.colorScheme.error : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                "$count · ${gradeAverageFormat.format(share)} %",
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: highlight ? FontWeight.bold : null,
                  color: highlight ? color : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total <= 0 ? 0 : count / total,
              minHeight: 6,
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.hint});

  final String label, value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: hint == null ? null : Text(hint!),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _GradeStatistics extends StatelessWidget {
  const _GradeStatistics({required this.grades});

  final GradesState grades;

  String _grade(double scaledByHundred) =>
      gradeAverageFormat.format(scaledByHundred / 100);

  @override
  Widget build(BuildContext context) {
    final semester = grades.semester;
    final all = <GradeAll>[];
    final perSubject = <String, double>{};
    final countPerSubject = <String, int>{};

    for (final subject in grades.subjects) {
      final subjectGrades = subject.basicGrades(semester) ?? const <GradeAll>[];
      final counting = subjectGrades.where(countsTowardsAverage).toList();
      all.addAll(subjectGrades);
      final average = GradeStats.weightedAverage(subjectGrades);
      if (average != null) {
        perSubject[subject.name] = average;
        countPerSubject[subject.name] = counting.length;
      }
    }

    final overall = GradeStats.weightedAverage(all);
    if (overall == null) {
      return const _Section(
        title: "Noten",
        children: [],
        emptyText: "Noch keine Noten geladen.",
      );
    }

    final spread = GradeStats.spread(all)!;
    final trend = GradeStats.trendPerMonth(all);
    final improvement = GradeStats.improvement(all);
    final byType = GradeStats.averageByType(all);
    final sorted = perSubject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final perMonth = <String, int>{};
    for (final grade in all.where(countsTowardsAverage)) {
      final key = "${grade.date.year}-"
          "${grade.date.month.toString().padLeft(2, "0")}";
      perMonth.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    final countingTotal = all.where(countsTowardsAverage).length;

    return _Section(
      title: "Noten",
      children: [
        _Row(label: "Gesamtschnitt", value: _grade(overall)),
        _Row(label: "Anzahl Noten", value: "$countingTotal"),
        _Row(label: "Beste Note", value: _grade(spread.best)),
        _Row(label: "Schlechteste Note", value: _grade(spread.worst)),
        _Row(
          label: "Streuung",
          value: "± ${_grade(spread.standardDeviation)}",
          hint: "Je kleiner, desto gleichmäßiger",
        ),
        if (trend != null)
          _Row(
            label: "Trend pro Monat",
            value: "${trend >= 0 ? "+" : ""}"
                "${gradeAverageFormat.format(trend)}",
          ),
        if (improvement != null)
          _Row(
            label: "2. gegen 1. Hälfte",
            value: "${improvement >= 0 ? "+" : ""}"
                "${gradeAverageFormat.format(improvement)}",
          ),
        if (sorted.isNotEmpty) ...[
          const Divider(),
          const _SubHeading("Nach Fach"),
          for (final entry in sorted)
            _Row(
              label: entry.key,
              value: _grade(entry.value),
              hint: "${countPerSubject[entry.key]} Noten",
            ),
          _Row(label: "Bestes Fach", value: sorted.first.key),
          _Row(label: "Schwächstes Fach", value: sorted.last.key),
        ],
        if (byType.length > 1) ...[
          const Divider(),
          const _SubHeading("Nach Art der Bewertung"),
          for (final entry in byType.entries)
            _Row(label: entry.key, value: _grade(entry.value)),
        ],
        if (perMonth.length > 1) ...[
          const Divider(),
          const _SubHeading("Noten pro Monat"),
          for (final entry in (perMonth.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
            _BarRow(
              label: _monthLabel(entry.key),
              count: entry.value,
              total: countingTotal,
            ),
        ],
      ],
    );
  }
}

class _AbsenceStatistics extends StatelessWidget {
  const _AbsenceStatistics({
    required this.absences,
    required this.calendar,
    required this.limitPercentage,
    required this.lessonTimes,
  });

  final AbsencesState absences;
  final CalendarState calendar;
  final int limitPercentage;
  final List<LessonTime> lessonTimes;

  @override
  Widget build(BuildContext context) {
    final statistic = absences.statistic;
    final groups = absences.absences.toList();
    if (statistic == null) {
      return const _Section(
        title: "Absenzen",
        children: [],
        emptyText: "Noch keine Absenzen geladen.",
      );
    }

    final missed = AbsenceStats.missedLessons(groups);
    final percentage = AbsenceStats.missedPercentage(statistic);
    final budget = AbsenceStats.budget(
      statistic: statistic,
      absences: groups,
      limitPercentage: limitPercentage.toDouble(),
    );

    final byWeekday = AbsenceStats.missedByWeekday(groups);
    final byLesson = AbsenceStats.missedByLesson(groups);
    final byMonth = AbsenceStats.missedByMonth(groups);
    final bySubject =
        AbsenceStats.missedBySubject(absences: groups, calendar: calendar);

    final lessonTotal = byLesson.values.fold<int>(0, (a, b) => a + b);
    final weekdayTotal = byWeekday.values.fold<int>(0, (a, b) => a + b);
    final monthTotal = byMonth.values.fold<int>(0, (a, b) => a + b);
    final subjectTotal =
        bySubject.bySubject.values.fold<int>(0, (a, b) => a + b);

    final worstLesson = _largestKey(byLesson);
    final worstWeekday = _largestKey(byWeekday);

    return _Section(
      title: "Absenzen",
      children: [
        _Row(label: "Versäumte Stunden", value: "${missed.round()}"),
        if (percentage != null)
          _Row(
            label: "Anteil",
            value: "${gradeAverageFormat.format(percentage)} %",
          ),
        if (statistic.counter != null)
          _Row(label: "Absenzen", value: "${statistic.counter}"),
        if (statistic.justified != null)
          _Row(label: "Entschuldigt", value: "${statistic.justified}"),
        if (statistic.notJustified != null)
          _Row(label: "Nicht entschuldigt", value: "${statistic.notJustified}"),
        if (statistic.delayed != null)
          _Row(label: "Verspätungen", value: "${statistic.delayed}"),
        if (statistic.counterForSchool != null)
          _Row(
            label: "Im Auftrag der Schule",
            value: "${statistic.counterForSchool}",
          ),
        if (budget != null) ...[
          const Divider(),
          const _SubHeading("Budget"),
          _Row(
            label: "Stunden im Schuljahr",
            value: "rund ${budget.estimatedTotalLessons.round()}",
            hint: "Aus dem Prozentsatz zurückgerechnet",
          ),
          _Row(
            label: budget.exceeded ? "Über der Grenze" : "Noch möglich",
            value: budget.exceeded
                ? "${(-budget.remainingLessons).ceil()} Stunden"
                : "${budget.remainingLessons.floor()} Stunden",
            hint: "Grenze: $limitPercentage %",
          ),
        ],
        if (byLesson.isNotEmpty) ...[
          const Divider(),
          _SubHeading(
            "Nach Stunde",
            hint: worstLesson == null
                ? null
                : "Am häufigsten fehlst du in der "
                    "${LessonTimes.label(lessonTimes, worstLesson)}",
          ),
          for (final entry in (byLesson.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
            _BarRow(
              label: LessonTimes.label(lessonTimes, entry.key),
              count: entry.value,
              total: lessonTotal,
              highlight: entry.key == worstLesson,
            ),
        ],
        if (byWeekday.isNotEmpty) ...[
          const Divider(),
          _SubHeading(
            "Nach Wochentag",
            hint: worstWeekday == null
                ? null
                : "Am häufigsten am ${_weekdayNames[worstWeekday]}",
          ),
          for (final entry in (byWeekday.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
            _BarRow(
              label: _weekdayNames[entry.key] ?? "?",
              count: entry.value,
              total: weekdayTotal,
              highlight: entry.key == worstWeekday,
            ),
        ],
        if (bySubject.bySubject.isNotEmpty) ...[
          const Divider(),
          _SubHeading(
            "Nach Fach",
            hint: bySubject.unmatched > 0
                ? "${bySubject.unmatched} Stunden lassen sich nicht zuordnen – "
                    "der Kalender ist nur für die geladenen Wochen bekannt"
                : null,
          ),
          for (final entry in (bySubject.bySubject.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value))))
            _BarRow(
              label: entry.key,
              count: entry.value,
              total: subjectTotal,
            ),
        ] else ...[
          const Divider(),
          const _SubHeading(
            "Nach Fach",
            hint: "Dafür muss der Kalender geladen sein – einmal öffnen "
                "genügt, dann zählt die Woche hier mit",
          ),
        ],
        if (byMonth.length > 1) ...[
          const Divider(),
          const _SubHeading("Nach Monat"),
          for (final entry in (byMonth.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))))
            _BarRow(
              label: _monthLabel(entry.key),
              count: entry.value,
              total: monthTotal,
            ),
        ],
      ],
    );
  }
}

class _EntryStatistics extends StatelessWidget {
  const _EntryStatistics({required this.dashboard, required this.calendar});

  final DashboardState dashboard;
  final CalendarState calendar;

  @override
  Widget build(BuildContext context) {
    final entries = Agenda.collect(calendar: calendar, dashboard: dashboard);
    if (entries.isEmpty) {
      return const _Section(
        title: "Einträge",
        children: [],
        emptyText: "Noch nichts geladen.",
      );
    }

    final seen = <String>{};
    final unique = entries.where((e) => seen.add(e.identity)).toList();
    final exams = unique.where((e) => e.isExam).length;
    final homework = unique.length - exams;

    final perSubject = <String, int>{};
    for (final entry in unique) {
      if (entry.subject.isEmpty) continue;
      perSubject.update(entry.subject, (v) => v + 1, ifAbsent: () => 1);
    }

    return _Section(
      title: "Einträge",
      children: [
        _Row(label: "Prüfungen und Tests", value: "$exams"),
        _Row(label: "Hausaufgaben", value: "$homework"),
        if (perSubject.isNotEmpty) ...[
          const Divider(),
          const _SubHeading("Nach Fach"),
          for (final entry in (perSubject.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value))))
            _BarRow(
              label: entry.key,
              count: entry.value,
              total: unique.length,
            ),
        ],
      ],
    );
  }
}

class _YearStatistics extends StatelessWidget {
  const _YearStatistics({required this.holidays, required this.lastSchoolDay});

  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;

  @override
  Widget build(BuildContext context) {
    final nextHolidays = SchoolYear.nextHolidays(holidays, now: now);
    final lastDay = SchoolYear.lastDay(lastSchoolDay, now: now);
    final schoolDaysLeft = lastSchoolDay == null
        ? null
        : SchoolYear.schoolDaysBetween(now, lastSchoolDay!,
            holidays: holidays);

    return _Section(
      title: "Schuljahr",
      emptyText: "In den Einstellungen unter „Schuljahr“ eintragen.",
      children: [
        if (nextHolidays != null)
          _Row(
            label: nextHolidays.label,
            value: nextHolidays.daysLabel,
            hint: nextHolidays.ongoing ? "Läuft gerade" : "Nächste Ferien",
          ),
        if (lastDay != null)
          _Row(label: "Schulende", value: lastDay.daysLabel),
        if (schoolDaysLeft != null && schoolDaysLeft > 0) ...[
          _Row(label: "Schultage übrig", value: "$schoolDaysLeft"),
          _Row(
            label: "Schulwochen übrig",
            value: gradeAverageFormat.format(schoolDaysLeft / 5),
          ),
        ],
      ],
    );
  }
}

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.titleSmall),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Turns `2026-09` into `September 2026`.
String _monthLabel(String key) {
  final parts = key.split("-");
  if (parts.length != 2) return key;
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return key;
  return "${_monthNames[month - 1]} ${parts[0]}";
}

K? _largestKey<K>(Map<K, int> values) {
  K? best;
  var bestCount = -1;
  for (final entry in values.entries) {
    if (entry.value > bestCount) {
      bestCount = entry.value;
      best = entry.key;
    }
  }
  return best;
}
