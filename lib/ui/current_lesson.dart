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

/// The lesson going on right now, next to the page title (#26).
library;

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_time.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// A page title with the current lesson and its countdown beside it.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 12),
        const Flexible(child: CurrentLessonIndicator()),
      ],
    );
  }
}

/// "Mathematik · noch 23:14" while a lesson is on, "Pause · noch 8:30 → Ita"
/// in a break, nothing otherwise. A double lesson counts down to the end of
/// both, with the end of the current hour in brackets.
class CurrentLessonIndicator extends StatelessWidget {
  const CurrentLessonIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions,
        (CalendarState, BuiltList<LessonTime>, BuiltMap<String, String>, bool)>(
      connect: (state) => (
        state.calendarState,
        state.settingsState.lessonSchedule,
        state.settingsState.subjectNicks,
        state.settingsState.showSchoolEndCountdown,
      ),
      builder: (context, vm, actions) {
        final times = LessonTimes.resolve(vm.$2);
        return SchoolClock(
          interval: const Duration(seconds: 1),
          builder: (context, now) {
            final end = schoolEnd(vm.$1, times, now);
            final lesson = currentLesson(vm.$1, times, now);
            if (lesson != null) {
              return CurrentLessonChip(
                subject: subjectNick(vm.$3, lesson.subject),
                lesson: lesson,
                now: now,
                schoolEnd: end,
                showSchoolEnd: vm.$4,
              );
            }
            final pause = currentBreak(vm.$1, times, now);
            if (pause == null) return const SizedBox.shrink();
            return CountdownChip(
              icon: Icons.free_breakfast_outlined,
              text: breakLabel(subjectNick(vm.$3, pause.subject), pause.start,
                  now, vm.$4 ? end : null),
              tooltip: [
                "Pause bis ${_clock(pause.start)}, dann ${pause.subject}",
                if (end != null) schoolEndLabel(end, now),
              ].join("\n"),
            );
          },
        );
      },
    );
  }
}

String subjectNick(BuiltMap<String, String> nicks, String subject) {
  for (final entry in nicks.entries) {
    if (entry.key.toLowerCase() == subject.toLowerCase()) return entry.value;
  }
  return subject;
}

String _clock(UtcDateTime t) =>
    "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}";

/// "Schulschluss in 2:15:00".
String schoolEndLabel(UtcDateTime end, UtcDateTime now) =>
    "Schulschluss in ${CurrentLessonChip.countdown(end.difference(now))}";

/// "Pause · noch 8:30 → Ita", with the school end when [end] is given.
String breakLabel(
    String next, UtcDateTime start, UtcDateTime now, UtcDateTime? end) {
  final text =
      "Pause · noch ${CurrentLessonChip.countdown(start.difference(now))} → $next";
  return end == null ? text : "$text · ${schoolEndLabel(end, now)}";
}

class CurrentLessonChip extends StatelessWidget {
  const CurrentLessonChip({
    super.key,
    required this.subject,
    required this.lesson,
    required this.now,
    this.schoolEnd,
    this.showSchoolEnd = false,
  });

  final String subject;
  final CurrentLesson lesson;
  final UtcDateTime now;

  /// When school is over today; always in the tooltip, in the chip itself
  /// only with [showSchoolEnd].
  final UtcDateTime? schoolEnd;
  final bool showSchoolEnd;

  static String countdown(Duration left) {
    final seconds = left.inSeconds < 0 ? 0 : left.inSeconds;
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    String two(int v) => v.toString().padLeft(2, "0");
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "$m:${two(s)}";
  }

  /// "Mat · noch 1:30:15 (40:15)": in the first hour of a double lesson the
  /// end of that hour in brackets.
  static String label(String subject, CurrentLesson lesson, UtcDateTime now) {
    final total = "$subject · noch ${countdown(lesson.remaining(now))}";
    return lesson.isDouble
        ? "$total (${countdown(lesson.remainingInLesson(now))})"
        : total;
  }

  @override
  Widget build(BuildContext context) {
    final hours = lesson.fromHour == lesson.toHour
        ? "${lesson.fromHour}. Stunde"
        : "${lesson.fromHour}.–${lesson.toHour}. Stunde";
    final end = schoolEnd;
    // The school end only when it is not just the end of this lesson.
    final showEnd = end != null && end != lesson.end;
    return CountdownChip(
      icon: Icons.schedule,
      text: [
        label(subject, lesson, now),
        if (showSchoolEnd && showEnd) schoolEndLabel(end, now),
      ].join(" · "),
      tooltip: [
        "$hours · bis ${_clock(lesson.end)}",
        if (showEnd) schoolEndLabel(end, now),
      ].join("\n"),
    );
  }
}

/// The rounded chip the countdowns are shown in.
class CountdownChip extends StatelessWidget {
  const CountdownChip({
    super.key,
    required this.icon,
    required this.text,
    required this.tooltip,
  });

  final IconData icon;
  final String text;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
