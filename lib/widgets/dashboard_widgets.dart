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

/// The cards on the dashboard.
///
/// Each card gets the data it needs handed to it and a [DashboardWidgetConfig]
/// that says what the user wants to see in it. They are deliberately dumb: the
/// store connection lives in `container/dashboard_widgets_container.dart`.
library;

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_year.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/widgets/vanishing_list.dart';
import 'package:dr/widgets/widget_catalog.dart';
import 'package:flutter/material.dart';

/// Everything the cards read, gathered once so they all agree on the clock.
class DashboardWidgetData {
  const DashboardWidgetData({
    required this.now,
    required this.calendar,
    required this.dashboard,
    required this.absences,
    required this.grades,
    required this.messages,
    required this.holidays,
    required this.lastSchoolDay,
    required this.absenceLimitPercentage,
    required this.weeklyLessons,
    required this.lessonTimes,
  });

  final UtcDateTime now;
  final CalendarState calendar;
  final DashboardState dashboard;
  final AbsencesState absences;
  final GradesState grades;
  final MessagesState messages;
  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final int absenceLimitPercentage;
  final int weeklyLessons;

  /// When the lessons of a day run, already resolved against the calendar.
  final List<LessonTime> lessonTimes;
}

/// Builds the card for [config], or nothing when the type is unknown.
Widget buildDashboardWidget({
  required DashboardWidgetConfig config,
  required DashboardWidgetData data,
  VoidCallback? onOpenCalendar,
  VoidCallback? onOpenAbsences,
  VoidCallback? onOpenGrades,
  VoidCallback? onOpenMessages,
}) {
  switch (config.type) {
    case upcomingWidgetId:
      return _UpcomingCard(config: config, data: data);
    case tomorrowWidgetId:
      return _DayCard(
        config: config,
        data: data,
        day: data.now.add(const Duration(days: 1)),
        title: "Morgen",
        icon: Icons.today,
        onOpenCalendar: onOpenCalendar,
      );
    case todayWidgetId:
      return _DayCard(
        config: config,
        data: data,
        day: data.now,
        title: "Heute",
        icon: Icons.wb_sunny_outlined,
        onOpenCalendar: onOpenCalendar,
      );
    case gradesWidgetId:
      return _GradesCard(
          config: config, data: data, onOpenGrades: onOpenGrades);
    case absencesWidgetId:
      return _AbsencesCard(
          config: config, data: data, onOpenAbsences: onOpenAbsences);
    case holidaysWidgetId:
      return _HolidaysCard(
          config: config, data: data, onOpenCalendar: onOpenCalendar);
    case messagesWidgetId:
      return _MessagesCard(
          config: config, data: data, onOpenMessages: onOpenMessages);
    default:
      return const SizedBox.shrink();
  }
}

/// The frame every card shares: a title row, an optional action and the body.
class _WidgetCard extends StatelessWidget {
  const _WidgetCard({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
    this.onTapTitle,
    this.emptyText,
    this.isEmpty,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;
  final VoidCallback? onTapTitle;

  /// Shown in addition to [children] when there is nothing to list.
  final String? emptyText;

  /// Whether the card has anything to say. Defaults to "no children", but a
  /// card whose rows animate themselves away always has a child, so it says so
  /// explicitly.
  final bool? isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTapTitle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  if (trailing != null) trailing!,
                  if (onTapTitle != null)
                    const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
          if ((isEmpty ?? children.isEmpty) && emptyText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(emptyText!, style: theme.textTheme.bodySmall),
            ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.config, required this.data});

  final DashboardWidgetConfig config;
  final DashboardWidgetData data;

  @override
  Widget build(BuildContext context) {
    var entries = ExamCountdown.upcoming(
      data.calendar,
      dashboard: data.dashboard,
      now: data.now,
      within: Duration(days: config.daysAhead),
      includeHomework: config.includeHomework,
      includeExams: config.includeExams,
    );
    if (config.maxEntries > 0 && entries.length > config.maxEntries) {
      entries = entries.sublist(0, config.maxEntries);
    }

    return _WidgetCard(
      title: "Demnächst",
      icon: Icons.timer_outlined,
      isEmpty: entries.isEmpty,
      emptyText: config.includeExams && !config.includeHomework
          ? "In den nächsten ${config.daysAhead} Tagen ist keine Prüfung "
              "eingetragen."
          : "In den nächsten ${config.daysAhead} Tagen ist nichts eingetragen.",
      children: [
        // Ticking something off on the dashboard removes it here; the list
        // animates the row away rather than letting it blink out.
        VanishingList(
          items: [
            for (final entry in entries)
              VanishingItem(
                id: entry.identity,
                child: ListTile(
                  dense: true,
                  leading:
                      _DaysChip(days: entry.daysFrom(data.now), entry: entry),
                  title: Text(entry.name),
                  subtitle: config.compact
                      ? null
                      : Text(
                          [entry.subject, entry.typeName]
                              .where((s) => s.isNotEmpty)
                              .join(" · "),
                        ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Heute" and "Morgen" — the same card with a different day.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.config,
    required this.data,
    required this.day,
    required this.title,
    required this.icon,
    this.onOpenCalendar,
  });

  final DashboardWidgetConfig config;
  final DashboardWidgetData data;
  final UtcDateTime day;
  final String title;
  final IconData icon;
  final VoidCallback? onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var entries = Agenda.forDay(
      calendar: data.calendar,
      dashboard: data.dashboard,
      day: day,
      includeExams: config.includeExams,
      includeHomework: config.includeHomework,
    );
    if (config.maxEntries > 0 && entries.length > config.maxEntries) {
      entries = entries.sublist(0, config.maxEntries);
    }

    final lessons =
        config.includeLessons ? Agenda.lessonsOn(data.calendar, day) : const [];

    return _WidgetCard(
      title: "$title: ${Day.format(UtcDateTime(day.year, day.month, day.day))}",
      icon: icon,
      onTapTitle: onOpenCalendar,
      isEmpty: entries.isEmpty && lessons.isEmpty,
      emptyText: "Nichts eingetragen.",
      children: [
        VanishingList(
          items: [
            for (final entry in entries)
              VanishingItem(
                id: entry.identity,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    entry.isExam
                        ? Icons.assignment_late
                        : Icons.assignment_outlined,
                    color: entry.isExam ? theme.colorScheme.error : null,
                  ),
                  title: Text(entry.name),
                  subtitle: config.compact
                      ? null
                      : Text(
                          [entry.subject, entry.typeName]
                              .where((s) => s.isNotEmpty)
                              .join(" · "),
                        ),
                ),
              ),
          ],
        ),
        if (lessons.isNotEmpty) ...[
          if (entries.isNotEmpty) const Divider(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: _LessonList(
              lessons: lessons.cast<CalendarHour>(),
              times: data.lessonTimes,
            ),
          ),
        ] else if (config.includeLessons)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              "Die Stunden stehen im Kalender – einmal öffnen, dann sind sie "
              "auch hier.",
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// The lessons of a day, one row each, with the breaks drawn as empty space.
///
/// Reading a timetable is much easier when the long break is visible as a gap
/// than when every row looks the same.
class _LessonList extends StatelessWidget {
  const _LessonList({required this.lessons, required this.times});

  final List<CalendarHour> lessons;
  final List<LessonTime> times;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breaks = LessonTimes.breaksBefore(times);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final lesson in lessons) ...[
          SizedBox(height: LessonTimes.spacingBefore(breaks[lesson.fromHour])),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  lesson.fromHour == lesson.toHour
                      ? "${lesson.fromHour}."
                      : "${lesson.fromHour}.–${lesson.toHour}.",
                  style: theme.textTheme.labelMedium,
                ),
              ),
              Expanded(
                child: Text(
                  lesson.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _timeLabel(lesson),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The block's own span when the calendar knows it, otherwise the configured
  /// times of its first and last lesson.
  String _timeLabel(CalendarHour lesson) {
    final start = LessonTimes.forHour(times, lesson.fromHour);
    final end = LessonTimes.forHour(times, lesson.toHour);
    if (start == null) return "";
    if (end == null || end.hour == start.hour) return start.rangeLabel;
    return "${start.startLabel}–${end.endLabel}";
  }
}

class _GradesCard extends StatelessWidget {
  const _GradesCard({
    required this.config,
    required this.data,
    this.onOpenGrades,
  });

  final DashboardWidgetConfig config;
  final DashboardWidgetData data;
  final VoidCallback? onOpenGrades;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semester = data.grades.semester;

    final perSubject = <MapEntry<String, double>>[];
    final everything = <GradeAll>[];
    for (final subject in data.grades.subjects) {
      final grades = subject.basicGrades(semester) ?? const <GradeAll>[];
      everything.addAll(grades);
      final average = GradeStats.weightedAverage(grades);
      if (average != null) perSubject.add(MapEntry(subject.name, average));
    }
    perSubject.sort((a, b) => a.value.compareTo(b.value));

    final overall = GradeStats.weightedAverage(everything);
    final trend = GradeStats.trendPerMonth(everything);

    var worst = perSubject;
    if (config.maxEntries > 0 && worst.length > config.maxEntries) {
      worst = worst.sublist(0, config.maxEntries);
    }

    return _WidgetCard(
      title: "Noten",
      icon: Icons.grade_outlined,
      onTapTitle: onOpenGrades,
      emptyText: "Noch keine Noten geladen.",
      trailing: overall == null
          ? null
          : Text(
              gradeAverageFormat.format(overall / 100),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
      children: [
        if (overall != null) ...[
          if (trend != null && !config.compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                trend >= 0.05
                    ? "Es geht aufwärts (+${gradeAverageFormat.format(trend)} "
                        "pro Monat)."
                    : trend <= -0.05
                        ? "Es geht abwärts "
                            "(${gradeAverageFormat.format(trend)} pro Monat)."
                        : "Der Schnitt ist stabil.",
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final entry in worst)
            ListTile(
              dense: true,
              title: Text(entry.key),
              trailing: Text(
                gradeAverageFormat.format(entry.value / 100),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: entry.value < 600 ? theme.colorScheme.error : null,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AbsencesCard extends StatelessWidget {
  const _AbsencesCard({
    required this.config,
    required this.data,
    this.onOpenAbsences,
  });

  final DashboardWidgetConfig config;
  final DashboardWidgetData data;
  final VoidCallback? onOpenAbsences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statistic = data.absences.statistic;
    final percentage = AbsenceStats.missedPercentage(statistic);
    final budget = AbsenceStats.budget(
      statistic: statistic,
      absences: data.absences.absences,
      limitPercentage: data.absenceLimitPercentage.toDouble(),
    );
    final open = AbsenceStats.notYetJustifiedCount(data.absences.absences);

    return _WidgetCard(
      title: "Absenzen",
      icon: Icons.hotel,
      onTapTitle: onOpenAbsences,
      emptyText: "Absenzen einmal öffnen, dann stehen sie auch hier.",
      trailing: percentage == null
          ? null
          : Text(
              "${gradeAverageFormat.format(percentage)} %",
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
      children: [
        if (percentage != null) ...[
          if (budget != null)
            ListTile(
              dense: true,
              title: Text(
                budget.exceeded
                    ? "Die Grenze von ${data.absenceLimitPercentage} % ist "
                        "überschritten"
                    : "Noch ${budget.remainingLessons.floor()} Stunden bis zur "
                        "Grenze",
              ),
              subtitle: config.compact
                  ? null
                  : Text("${AbsenceStats.missedLessons(data.absences.absences)
                      .round()} von rund "
                      "${budget.estimatedTotalLessons.round()} Stunden "
                      "versäumt"),
            ),
          if (open > 0)
            ListTile(
              dense: true,
              leading: Icon(Icons.warning_amber, color: theme.colorScheme.error),
              title: Text(open == 1
                  ? "Eine Absenz wartet auf eine Entschuldigung"
                  : "$open Absenzen warten auf eine Entschuldigung"),
            ),
        ],
      ],
    );
  }
}

class _HolidaysCard extends StatelessWidget {
  const _HolidaysCard({
    required this.config,
    required this.data,
    this.onOpenCalendar,
  });

  final DashboardWidgetConfig config;
  final DashboardWidgetData data;
  final VoidCallback? onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final holidays = SchoolYear.nextHolidays(data.holidays, now: data.now);
    final lastDay = SchoolYear.lastDay(data.lastSchoolDay, now: data.now);

    return _WidgetCard(
      title: "Ferien",
      icon: Icons.beach_access_outlined,
      emptyText: "Keine Ferien eingetragen – in den Einstellungen nachtragen.",
      children: [
        for (final countdown in [holidays, lastDay].whereType<Countdown>())
          ListTile(
            dense: true,
            title: Text(countdown.label),
            subtitle: config.compact
                ? null
                : Text(_formatDate(countdown.date)),
            trailing: Text(
              countdown.daysLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: onOpenCalendar,
          ),
      ],
    );
  }
}

class _MessagesCard extends StatelessWidget {
  const _MessagesCard({
    required this.config,
    required this.data,
    this.onOpenMessages,
  });

  final DashboardWidgetConfig config;
  final DashboardWidgetData data;
  final VoidCallback? onOpenMessages;

  @override
  Widget build(BuildContext context) {
    var unread = data.messages.messages.where((m) => m.isNew).toList()
      ..sort((a, b) => -a.timeSent.compareTo(b.timeSent));
    final total = unread.length;
    if (config.maxEntries > 0 && unread.length > config.maxEntries) {
      unread = unread.sublist(0, config.maxEntries);
    }

    return _WidgetCard(
      title: "Mitteilungen",
      icon: Icons.mail_outline,
      onTapTitle: onOpenMessages,
      emptyText: "Keine ungelesenen Mitteilungen.",
      trailing: total == 0
          ? null
          : Text("$total",
              style: const TextStyle(fontWeight: FontWeight.bold)),
      children: [
        for (final message in unread)
          ListTile(
            dense: true,
            title: Text(message.subject, maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: config.compact ? null : Text(message.fromName),
            onTap: onOpenMessages,
          ),
      ],
    );
  }
}

class _DaysChip extends StatelessWidget {
  const _DaysChip({required this.days, required this.entry});

  final int days;
  final UpcomingExam entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = days <= 2;
    final color = entry.warning || urgent
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            days <= 0 ? "!" : "$days",
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            days <= 0
                ? "heute"
                : days == 1
                    ? "Tag"
                    : "Tage",
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

String _formatDate(UtcDateTime date) =>
    "${date.day}.${date.month}.${date.year}";
