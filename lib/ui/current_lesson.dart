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

/// "Mathematik · noch 23:14" while a lesson is on, nothing otherwise. A
/// double lesson counts down to the end of both.
class CurrentLessonIndicator extends StatelessWidget {
  const CurrentLessonIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions,
        (CalendarState, BuiltList<LessonTime>, BuiltMap<String, String>)>(
      connect: (state) => (
        state.calendarState,
        state.settingsState.lessonSchedule,
        state.settingsState.subjectNicks,
      ),
      builder: (context, vm, actions) {
        final times = LessonTimes.resolve(vm.$2);
        return SchoolClock(
          interval: const Duration(seconds: 1),
          builder: (context, now) {
            final lesson = currentLesson(vm.$1, times, now);
            if (lesson == null) return const SizedBox.shrink();
            return CurrentLessonChip(
              subject: _nick(vm.$3, lesson.subject),
              lesson: lesson,
              now: now,
            );
          },
        );
      },
    );
  }

  static String _nick(BuiltMap<String, String> nicks, String subject) {
    for (final entry in nicks.entries) {
      if (entry.key.toLowerCase() == subject.toLowerCase()) return entry.value;
    }
    return subject;
  }
}

class CurrentLessonChip extends StatelessWidget {
  const CurrentLessonChip({
    super.key,
    required this.subject,
    required this.lesson,
    required this.now,
  });

  final String subject;
  final CurrentLesson lesson;
  final UtcDateTime now;

  static String countdown(Duration left) {
    final seconds = left.inSeconds < 0 ? 0 : left.inSeconds;
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    String two(int v) => v.toString().padLeft(2, "0");
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "$m:${two(s)}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = lesson.fromHour == lesson.toHour
        ? "${lesson.fromHour}. Stunde"
        : "${lesson.fromHour}.–${lesson.toHour}. Stunde";
    return Tooltip(
      message: "$hours · bis ${lesson.end.hour.toString().padLeft(2, "0")}:"
          "${lesson.end.minute.toString().padLeft(2, "0")}",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                "$subject · noch ${countdown(lesson.remaining(now))}",
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
