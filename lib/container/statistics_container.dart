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
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/ui/statistics_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class StatisticsPageContainer extends StatelessWidget {
  const StatisticsPageContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, StatisticsViewModel>(
      connect: (state) => StatisticsViewModel(state),
      builder: (context, vm, actions) => _Statistics(vm: vm, actions: actions),
    );
  }
}

class StatisticsViewModel {
  StatisticsViewModel(AppState state)
      : grades = state.gradesState,
        absences = state.absencesState,
        calendar = state.calendarState,
        dashboard = state.dashboardState,
        limitPercentage = state.settingsState.absenceWarningThreshold,
        holidays = state.settingsState.holidays.toList(),
        lastSchoolDay = state.settingsState.lastSchoolDay,
        lessonTimes = LessonTimes.resolve(
          configured: state.settingsState.lessonTimes,
          calendar: state.calendarState,
          preferServer: state.settingsState.lessonTimesFromServer,
        ),
        loggedIn = state.loginState.loggedIn;

  final GradesState grades;
  final AbsencesState absences;
  final CalendarState calendar;
  final DashboardState dashboard;
  final int limitPercentage;
  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final List<LessonTime> lessonTimes;
  final bool loggedIn;

  bool get hasGrades => grades.subjects.isNotEmpty;
  bool get hasAbsences => absences.statistic != null;

  @override
  bool operator ==(Object other) =>
      other is StatisticsViewModel &&
      other.grades == grades &&
      other.absences == absences &&
      other.calendar == calendar &&
      other.dashboard == dashboard &&
      other.limitPercentage == limitPercentage &&
      other.lastSchoolDay == lastSchoolDay &&
      other.loggedIn == loggedIn &&
      BuiltList(other.holidays) == BuiltList(holidays);

  @override
  int get hashCode => Object.hash(grades, absences, calendar, dashboard,
      limitPercentage, lastSchoolDay, loggedIn, BuiltList(holidays));
}

/// Fetches what is missing, so the page is useful straight from the dashboard
/// without the user having had to visit grades and absences first.
class _Statistics extends StatefulWidget {
  const _Statistics({required this.vm, required this.actions});

  final StatisticsViewModel vm;
  final AppActions actions;

  @override
  State<_Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<_Statistics> {
  var _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_requested || !widget.vm.loggedIn) return;
      _requested = true;
      if (!widget.vm.hasGrades) {
        widget.actions.gradesActions.load(widget.vm.grades.semester);
      }
      if (!widget.vm.hasAbsences) widget.actions.absencesActions.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return StatisticsPage(
      grades: vm.grades,
      absences: vm.absences,
      calendar: vm.calendar,
      dashboard: vm.dashboard,
      limitPercentage: vm.limitPercentage,
      holidays: vm.holidays,
      lastSchoolDay: vm.lastSchoolDay,
      lessonTimes: vm.lessonTimes,
      loading: vm.grades.loading || (_requested && !vm.hasAbsences),
    );
  }
}
