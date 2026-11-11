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

/// The small lines above the entries of the register: how much of this
/// week's homework is done, weeks with many tests, and the school year in
/// review once it is over.
library;

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/stats.dart';
import 'package:dr/ui/year_review.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class DashboardHints extends StatelessWidget {
  const DashboardHints({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions,
        (DashboardState, UtcDateTime?, bool)>(
      connect: (state) => (
        state.dashboardState,
        state.settingsState.lastSchoolDay,
        state.settingsState.dashboardCompactView,
      ),
      builder: (context, vm, actions) {
        final today = now;
        final progress = WeekProgress.of(vm.$1, today);
        final dense = ExamDensity.perWeek(
          calendar: CalendarState(),
          dashboard: vm.$1,
          now: today,
        ).entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final review = showYearReviewBanner(vm.$2, today);
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (review)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text("Das Schuljahr ist um!"),
                    subtitle: const Text("Dein Rückblick wartet"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const YearReviewPageContainer(),
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  if (progress != null)
                    Expanded(child: WeekProgressBar(progress: progress))
                  else
                    const Spacer(),
                  IconButton(
                    tooltip: vm.$3 ? "Ausführliche Liste" : "Wochenübersicht",
                    icon: Icon(vm.$3
                        ? Icons.view_agenda_outlined
                        : Icons.calendar_view_week_outlined),
                    onPressed: () =>
                        actions.settingsActions.setDashboardCompactView(!vm.$3),
                  ),
                ],
              ),
              for (final week in dense.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "${_weekLabel(week.key, today)}: "
                          "${week.value} Prüfungen",
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _weekLabel(UtcDateTime monday, UtcDateTime today) {
    final week = "KW ${ExamDensity.weekNumber(monday)}";
    if (monday == toMonday(UtcDateTime(today.year, today.month, today.day))) {
      return "Diese Woche ($week)";
    }
    final friday = monday.add(const Duration(days: 4));
    return "$week (${monday.day}.${monday.month}.–${friday.day}.${friday.month}.)";
  }
}

/// "Diese Woche 7/9 erledigt" with a thin bar.
class WeekProgressBar extends StatelessWidget {
  const WeekProgressBar({super.key, required this.progress});

  final WeekProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = progress.done == progress.total;
    final color = complete ? Colors.green : theme.colorScheme.primary;
    return Tooltip(
      message: "Abgehakte Einträge von Montag bis Sonntag",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Diese Woche ${progress.done}/${progress.total} erledigt"
            "${complete ? " ✓" : ""}",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.share,
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
