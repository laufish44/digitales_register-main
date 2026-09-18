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
import 'package:dr/container/statistics_container.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/ui/absences_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class AbsencesPageContainer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AbsencesPageViewModel>(
      builder: (context, vm, actions) {
        return AbsencesPage(
          state: vm.state,
          noInternet: vm.noInternet,
          entryEnabled: vm.entryEnabled,
          warningEnabled: vm.warningEnabled,
          warningThreshold: vm.warningThreshold,
          maxHour: vm.maxHour,
          budgetEnabled: vm.budgetEnabled,
          weeklyLessons: vm.weeklyLessons,
          holidays: vm.holidays,
          lastSchoolDay: vm.lastSchoolDay,
          calendar: vm.calendar,
          lessonTimes: vm.lessonTimes,
          // The root navigator, not the nested one the content area uses, so
          // the page covers the whole window in tablet mode too.
          onShowStatistics: () => Navigator.of(context, rootNavigator: true)
              .push(
            MaterialPageRoute<void>(
              builder: (_) => const StatisticsPageContainer(),
            ),
          ),
          onAddFutureAbsence: actions.absencesActions.addFutureAbsence.call,
          onRemoveFutureAbsence:
              actions.absencesActions.removeFutureAbsence.call,
          onJustifyAbsence: actions.absencesActions.justifyAbsence.call,
        );
      },
      connect: (state) => AbsencesPageViewModel(state),
    );
  }
}

class AbsencesPageViewModel {
  AbsencesPageViewModel(AppState state)
      : this.state = state.absencesState,
        noInternet = state.noInternet,
        entryEnabled = state.settingsState.absenceEntryEnabled &&
            !state.isDemo &&
            state.absencesState.canEdit,
        warningEnabled = state.settingsState.absenceWarningEnabled,
        warningThreshold = state.settingsState.absenceWarningThreshold,
        budgetEnabled = state.settingsState.showAbsenceBudget,
        weeklyLessons = state.settingsState.weeklyLessons,
        holidays = state.settingsState.holidays.toList(),
        lastSchoolDay = state.settingsState.lastSchoolDay,
        calendar = state.calendarState,
        lessonTimes = LessonTimes.resolve(
          configured: state.settingsState.lessonTimes,
          calendar: state.calendarState,
          preferServer: state.settingsState.lessonTimesFromServer,
        ),
        maxHour = _maxHour(state);

  final AbsencesState state;
  final bool noInternet, entryEnabled, warningEnabled, budgetEnabled;
  final int warningThreshold, maxHour, weeklyLessons;
  final List<HolidayPeriod> holidays;
  final UtcDateTime? lastSchoolDay;
  final CalendarState calendar;
  final List<LessonTime> lessonTimes;

  /// The highest lesson number to offer in the picker.
  ///
  /// The timetable is the better source — it covers lessons this student does
  /// not have (the seventh, say) and is there before any calendar is loaded.
  static int _maxHour(AppState state) {
    var max = LessonTimes.maxHour(state.settingsState.lessonTimes);
    for (final day in state.calendarState.days.values) {
      for (final hour in day.hours) {
        if (hour.toHour > max) max = hour.toHour;
      }
    }
    return max;
  }

  @override
  bool operator ==(Object other) =>
      other is AbsencesPageViewModel &&
      other.state == state &&
      other.noInternet == noInternet &&
      other.entryEnabled == entryEnabled &&
      other.warningEnabled == warningEnabled &&
      other.warningThreshold == warningThreshold &&
      other.maxHour == maxHour &&
      other.budgetEnabled == budgetEnabled &&
      other.weeklyLessons == weeklyLessons &&
      other.lastSchoolDay == lastSchoolDay &&
      other.calendar == calendar &&
      BuiltList(other.holidays) == BuiltList(holidays);

  @override
  int get hashCode => Object.hash(state, noInternet, entryEnabled,
      warningEnabled, warningThreshold, maxHour, budgetEnabled, weeklyLessons,
      lastSchoolDay, calendar, BuiltList(holidays));
}
