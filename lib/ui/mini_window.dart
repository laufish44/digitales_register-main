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

/// The mini window on Windows: the app shrunk to a small tile that stays on
/// top, with the current lesson, its countdown and the next test — like a
/// desktop widget. The rest of the app keeps running behind it, so going
/// back is instant.
library;

import 'dart:io';

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/background/windows_window.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_time.dart';
import 'package:dr/stats.dart';
import 'package:dr/ui/current_lesson.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Whether the mini window is showing.
final miniWindow = ValueNotifier<bool>(false);

bool get miniWindowSupported => Platform.isWindows;

/// Switches between the mini window and the normal one.
void toggleMiniWindow() {
  if (!miniWindowSupported) return;
  if (miniWindow.value) {
    leaveMiniWindow();
    miniWindow.value = false;
  } else if (enterMiniWindow()) {
    miniWindow.value = true;
  }
}

/// The next test from today on, from the register's entries.
UpcomingExam? nextExam(AppState state, UtcDateTime now) {
  final today = UtcDateTime(now.year, now.month, now.day);
  final exams = Agenda.collect(
    calendar: state.calendarState,
    dashboard: state.dashboardState,
    includeCalendar: false,
  )
      // `warning` is the test flag; teacher homework is a "gradeGroup" too.
      .where((e) => e.warning && !e.isReminder && !e.deadline.isBefore(today))
      .toList()
    ..sort((a, b) => a.deadline.compareTo(b.deadline));
  return exams.isEmpty ? null : exams.first;
}

class MiniWindowView extends StatelessWidget {
  const MiniWindowView({super.key});

  @override
  Widget build(BuildContext context) {
    // Built above the app's navigator, so it brings its own overlay for the
    // tooltips.
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (context) => const _MiniContent()),
      ],
    );
  }
}

class _MiniContent extends StatelessWidget {
  const _MiniContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => startWindowDrag(),
        onDoubleTap: toggleMiniWindow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: StoreConnection<AppState, AppActions, AppState>(
                  connect: (state) => state,
                  builder: (context, state, actions) {
                    final exam = nextExam(state, now);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _LessonLine(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.grade,
                                size: 16, color: theme.colorScheme.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                exam == null
                                    ? "Keine Prüfung eingetragen"
                                    : "${exam.countdownLabel(now)}: "
                                        "${exam.name} ${exam.subject}",
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: "Normales Fenster",
                    icon: const Icon(Icons.open_in_full),
                    onPressed: toggleMiniWindow,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lesson or break countdown, or a note that there is no lesson.
class _LessonLine extends StatelessWidget {
  const _LessonLine();

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions,
        (CalendarState, BuiltList<LessonTime>)>(
      connect: (state) =>
          (state.calendarState, state.settingsState.lessonSchedule),
      builder: (context, vm, actions) {
        final times = LessonTimes.resolve(vm.$2);
        return SchoolClock(
          builder: (context, now) {
            final on = currentLesson(vm.$1, times, now) != null ||
                currentBreak(vm.$1, times, now) != null;
            if (on) return const CurrentLessonIndicator();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                vm.$1.days.isEmpty
                    ? "Kalender wird geladen"
                    : "Gerade kein Unterricht",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).disabledColor),
              ),
            );
          },
        );
      },
    );
  }
}
