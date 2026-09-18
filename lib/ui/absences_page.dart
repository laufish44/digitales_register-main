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

import 'package:dr/actions/absences_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/school_year.dart';
import 'package:dr/stats.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/ui/absence_entry.dart';
import 'package:dr/ui/insights.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class AbsencesPage extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final bool entryEnabled;
  final bool warningEnabled;
  final int warningThreshold;
  final int maxHour;
  final bool budgetEnabled;
  final int weeklyLessons;
  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final CalendarState calendar;
  final List<LessonTime> lessonTimes;
  final VoidCallback? onShowStatistics;
  final void Function(AddFutureAbsencePayload) onAddFutureAbsence;
  final void Function(FutureAbsence) onRemoveFutureAbsence;
  final void Function(JustifyAbsencePayload) onJustifyAbsence;

  const AbsencesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.entryEnabled,
    required this.warningEnabled,
    required this.warningThreshold,
    required this.maxHour,
    required this.budgetEnabled,
    required this.weeklyLessons,
    required this.holidays,
    required this.lastSchoolDay,
    required this.calendar,
    required this.lessonTimes,
    required this.onShowStatistics,
    required this.onAddFutureAbsence,
    required this.onRemoveFutureAbsence,
    required this.onJustifyAbsence,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: const Text("Absenzen"),
        actions: [
          if (onShowStatistics != null)
            IconButton(
              icon: const Icon(Icons.insights),
              tooltip: "Statistik",
              onPressed: onShowStatistics,
            ),
        ],
      ),
      body: LastFetchedOverlay(
        lastFetched: state.lastFetched,
        noInternet: noInternet,
        child: AbsencesBody(
          state: state,
          noInternet: noInternet,
          entryEnabled: entryEnabled,
          warningEnabled: warningEnabled,
          warningThreshold: warningThreshold,
          budgetEnabled: budgetEnabled,
          weeklyLessons: weeklyLessons,
          holidays: holidays,
          lastSchoolDay: lastSchoolDay,
          calendar: calendar,
          onRemoveFutureAbsence: onRemoveFutureAbsence,
          onJustifyAbsence: onJustifyAbsence,
        ),
      ),
      floatingActionButton: entryEnabled
          ? FloatingActionButton.extended(
              onPressed: state.submitting
                  ? null
                  : () => addFutureAbsence(
                        context,
                        maxHour: maxHour,
                        lessonTimes: lessonTimes,
                        onAdd: onAddFutureAbsence,
                      ),
              icon: const Icon(Icons.event_busy),
              // "Krank melden" and "vorentschuldigen" are the same thing on the
              // website: both ask for a range of lessons in the future (today
              // counts) and both end up at `absence_future`. Saying both here
              // saves people looking for a second button that does not exist.
              label: const Text("Krank melden / vorentschuldigen"),
            )
          : null,
    );
  }
}

/// Asks for an absence and hands it to [onAdd].
Future<void> addFutureAbsence(
  BuildContext context, {
  required int maxHour,
  required void Function(AddFutureAbsencePayload) onAdd,
  DateTime? initialDate,
  List<LessonTime> lessonTimes = const [],
}) async {
  final payload = await showAddFutureAbsenceDialog(
    context,
    maxHour: maxHour,
    initialDate: initialDate,
    lessonTimes: lessonTimes,
  );
  if (payload != null) onAdd(payload);
}

class AbsencesBody extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final bool entryEnabled;
  final bool warningEnabled;
  final int warningThreshold;
  final bool budgetEnabled;
  final int weeklyLessons;
  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final CalendarState calendar;
  final void Function(FutureAbsence) onRemoveFutureAbsence;
  final void Function(JustifyAbsencePayload) onJustifyAbsence;

  const AbsencesBody({
    super.key,
    required this.state,
    required this.noInternet,
    required this.entryEnabled,
    required this.warningEnabled,
    required this.warningThreshold,
    this.budgetEnabled = false,
    this.weeklyLessons = 0,
    this.holidays = const [],
    this.lastSchoolDay,
    required this.calendar,
    required this.onRemoveFutureAbsence,
    required this.onJustifyAbsence,
  });

  @override
  Widget build(BuildContext context) {
    if (state.statistic == null) {
      return noInternet
          ? const NoInternet()
          : const Center(child: CircularProgressIndicator());
    }

    final warning = warningEnabled
        ? AbsenceWarningBanner(
            statistic: state.statistic,
            threshold: warningThreshold,
            notYetJustified:
                AbsenceStats.notYetJustifiedCount(state.absences),
          )
        : const SizedBox.shrink();

    final budget = budgetEnabled
        ? AbsenceBudgetCard(
            statistic: state.statistic,
            absences: state.absences.toList(),
            limitPercentage: warningThreshold,
            weeklyLessons: weeklyLessons,
            holidays: holidays,
            lastSchoolDay: lastSchoolDay,
            calendar: calendar,
          )
        : const SizedBox.shrink();

    if (state.absences.isEmpty && state.futureAbsences.isEmpty) {
      return ListView(
        children: [
          warning,
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              "Noch keine Absenzen",
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView(children: <Widget>[
      warning,
      budget,
      AbsencesStatisticWidget(
        stat: state.statistic!,
      ),
      const Divider(height: 0),
      if (state.futureAbsences.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8.0).copyWith(top: 16),
          child: Text(
            "Im Voraus eingetragene Absenzen",
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      for (final futureAbsence in state.futureAbsences)
        FutureAbsenceWidget(
          absence: futureAbsence,
          onRemove: entryEnabled && !state.submitting
              ? () => _confirmRemove(context, futureAbsence)
              : null,
        ),
      if (state.absences.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8.0).copyWith(top: 16),
          child: Text(
            "Absenzen",
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ...List.generate(
        state.absences.length,
        (n) {
          final index = state.absences.length - n - 1;
          return AbsenceGroupContainer(
            group: index,
            onJustify: entryEnabled && !state.submitting
                ? () => _justify(context, state.absences[index])
                : null,
          );
        },
      ),
      const SizedBox(height: 80),
    ]);
  }

  Future<void> _confirmRemove(
      BuildContext context, FutureAbsence absence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Vorentschuldigung entfernen?"),
        content: const Text(
          "Die im Voraus eingetragene Absenz wird gelöscht.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Abbrechen"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Entfernen"),
          ),
        ],
      ),
    );
    if (confirmed == true) onRemoveFutureAbsence(absence);
  }

  Future<void> _justify(BuildContext context, AbsenceGroup group) async {
    final payload = await showJustifyAbsenceDialog(
      context,
      group: group,
      selfDeclarations: state.selfDeclarationActive
          ? state.selfDeclarations.toList()
          : const [],
      selfDeclarationMandatory: state.selfDeclarationMandatory,
    );
    if (payload != null) onJustifyAbsence(payload);
  }
}

/// "Du kannst noch X Stunden fehlen", and what that means in practice.
class AbsenceBudgetCard extends StatelessWidget {
  const AbsenceBudgetCard({
    super.key,
    required this.statistic,
    required this.absences,
    required this.limitPercentage,
    required this.weeklyLessons,
    required this.holidays,
    required this.lastSchoolDay,
    required this.calendar,
  });

  final AbsenceStatistic? statistic;
  final List<AbsenceGroup> absences;
  final int limitPercentage;

  /// 0 means "work it out from the calendar".
  final int weeklyLessons;

  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final CalendarState calendar;

  /// Lessons per week, from the setting or from the fullest week the calendar
  /// has seen. Null when neither is available.
  int? get _lessonsPerWeek {
    if (weeklyLessons > 0) return weeklyLessons;
    var best = 0;
    final perWeek = <UtcDateTime, int>{};
    for (final day in calendar.days.values) {
      final monday = toMonday(day.date);
      var lessons = 0;
      for (final hour in day.hours) {
        lessons += hour.length;
      }
      perWeek.update(monday, (v) => v + lessons, ifAbsent: () => lessons);
    }
    for (final lessons in perWeek.values) {
      if (lessons > best) best = lessons;
    }
    return best > 0 ? best : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = AbsenceStats.budget(
      statistic: statistic,
      absences: absences,
      limitPercentage: limitPercentage.toDouble(),
    );
    if (budget == null) {
      return const SizedBox.shrink();
    }

    final remaining = budget.remainingLessons;
    final perWeek = _lessonsPerWeek;
    final weeksLeft = _weeksLeft();

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: ExpansionTile(
        leading: Icon(
          budget.exceeded ? Icons.error_outline : Icons.timelapse,
          color: budget.exceeded ? theme.colorScheme.error : null,
        ),
        title: Text(
          budget.exceeded
              ? "Du bist ${(-remaining).ceil()} Stunden über der Grenze"
              : "Du kannst noch ${remaining.floor()} Stunden fehlen",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text("bis zur Grenze von $limitPercentage %"),
        children: [
          _row(
            context,
            "Bisher versäumt",
            "${AbsenceStats.missedLessons(absences).round()} Stunden "
                "(${gradeAverageFormat.format(budget.percentage)} %)",
          ),
          _row(
            context,
            "Stunden im Schuljahr",
            "rund ${budget.estimatedTotalLessons.round()}",
            hint: "Aus der Prozentangabe des Registers zurückgerechnet",
          ),
          _row(
            context,
            "Erlaubt bis zur Grenze",
            "${budget.allowedLessons.floor()} Stunden",
          ),
          if (!budget.exceeded && weeksLeft != null && weeksLeft > 0)
            _row(
              context,
              "Auf die restlichen Wochen verteilt",
              "${gradeAverageFormat.format(budget.perWeek(weeksLeft))} "
                  "Stunden pro Woche",
              hint: "$weeksLeft Schulwochen bis zum "
                  "${_formatDay(lastSchoolDay!)}",
            ),
          if (!budget.exceeded && perWeek != null)
            _row(
              context,
              "Das sind",
              "${gradeAverageFormat.format(remaining / perWeek)} ganze "
                  "Schulwochen",
              hint: weeklyLessons > 0
                  ? "$perWeek Stunden pro Woche (eingestellt)"
                  : "$perWeek Stunden pro Woche (aus dem Stundenplan)",
            ),
          if (!budget.exceeded && perWeek != null)
            _row(
              context,
              "Oder",
              "${(remaining / (perWeek / 5)).floor()} ganze Schultage",
              hint: "bei rund ${gradeAverageFormat.format(perWeek / 5)} "
                  "Stunden am Tag",
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// School weeks between today and the last day of school.
  double? _weeksLeft() {
    if (lastSchoolDay == null) return null;
    final days = SchoolYear.schoolDaysBetween(
      now,
      lastSchoolDay!,
      holidays: holidays,
    );
    if (days <= 0) return null;
    return days / 5;
  }

  Widget _row(BuildContext context, String label, String value,
      {String? hint}) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: hint == null ? null : Text(hint),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  static String _formatDay(UtcDateTime date) =>
      "${date.day}.${date.month}.${date.year}";
}

class AbsencesStatisticWidget extends StatelessWidget {
  final AbsenceStatistic stat;

  const AbsencesStatisticWidget({super.key, required this.stat});
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text("Statistik"),
      children: <Widget>[
        if (stat.counter != null)
          ListTile(
            title: const Text("Absenzen"),
            trailing: Text(stat.counter.toString()),
          ),
        if (stat.counterForSchool != null)
          ListTile(
            title: const Text("Absenzen im Auftrag der Schule"),
            trailing: Text(stat.counterForSchool.toString()),
          ),
        if (stat.delayed != null)
          ListTile(
            title: const Text("Verspätungen"),
            trailing: Text(stat.delayed.toString()),
          ),
        if (stat.justified != null)
          ListTile(
            title: const Text("Entschuldigte Absenzen"),
            trailing: Text(stat.justified.toString()),
          ),
        if (stat.notJustified != null)
          ListTile(
            title: const Text("Nicht entschuldigte Absenzen"),
            trailing: Text(stat.notJustified.toString()),
          ),
        if (stat.percentage != null)
          ListTile(
            title: const Text("Abwesenheit"),
            trailing: Text("${stat.percentage} %"),
          ),
      ],
    );
  }
}
