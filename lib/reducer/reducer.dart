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

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/actions/settings_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/reducer/absences.dart';
import 'package:dr/reducer/calendar.dart';
import 'package:dr/reducer/certificate.dart';
import 'package:dr/reducer/dashboard.dart';
import 'package:dr/reducer/grades.dart';
import 'package:dr/reducer/login.dart';
import 'package:dr/reducer/messages.dart';
import 'package:dr/reducer/network_protocol.dart';
import 'package:dr/reducer/notifications.dart';
import 'package:dr/reducer/profile_reducer.dart';
import 'package:dr/reducer/settings.dart';
import 'package:dr/school_year.dart';
import 'package:dr/util.dart';

final appReducerBuilder = ReducerBuilder<AppState, AppStateBuilder>()
  ..add(AppActionsNames.mountAppState, _mountState)
  ..add(AppActionsNames.noInternet, _noInternet)
  ..add(LoginActionsNames.loggingIn, _loggingIn)
  ..add(AppActionsNames.setConfig, _config)
  ..add(AppActionsNames.setUrl, _setUrl)
  ..combineNested(absencesReducerBuilder)
  ..combineNested(calendarReducerBuilder)
  ..combineNested(dashboardReducerBuilder)
  ..combineNested(gradesReducerBuilder)
  ..combineNested(loginReducerBuilder)
  ..combineNested(networkProtocolReducerBuilder)
  ..combineNested(notificationsReducerBuilder)
  ..combineNested(settingsReducerBuilder)
  ..combineNested(certificateReducerBuilder)
  ..combineNested(profileReducerBuilder)
  ..combineNested(messagesReducerBuilder)
  // Reducers for one action run in the order they were added, so these come
  // last: they correct what the nested reducers above have just done.
  ..add(AppActionsNames.mountAppState, _updateSchoolCalendar)
  ..add(AppActionsNames.mountAppState, _keepSingleSemester)
  ..add(AppActionsNames.setConfig, _keepSingleSemester)
  ..add(GradesActionsNames.setSemester, _keepSingleSemester)
  ..add(SettingsActionsNames.setSemestersPerYear, _keepSingleSemester);

/// With one semester per year there is nothing to pick: whatever the server
/// reports as current, or a state stored with "both semesters", the grades
/// show the first (and only) one.
void _keepSingleSemester(
    AppState state, Action<dynamic> action, AppStateBuilder builder) {
  if (builder.settingsState.semestersPerYear == 1) {
    builder.gradesState.semester.replace(Semester.first);
  }
}

/// Brings stored holidays and the last day of school to the built-in school
/// calendar: once when it gained a year (or a correction), and whenever the
/// stored ones belong to a school year that is over.
void _updateSchoolCalendar(
    AppState state, Action<dynamic> action, AppStateBuilder builder) {
  final settings = builder.settingsState;
  final outdated = schoolYearSettingsOutdated(
    settings.holidays.build(),
    settings.lastSchoolDay,
    now: now,
  );
  if (settings.schoolCalendarRevision == schoolCalendarRevision && !outdated) {
    return;
  }
  settings
    ..holidays.replace(holidaysForSchoolYear(now))
    ..lastSchoolDay = defaultLastSchoolDay
    ..schoolCalendarRevision = schoolCalendarRevision;
}

void _noInternet(AppState state, Action<bool> action, AppStateBuilder builder) {
  builder.noInternet = action.payload;
}

void _loggingIn(AppState state, Action<void> action, AppStateBuilder builder) {
  builder.noInternet = false;
}

void _config(AppState state, Action<Config> action, AppStateBuilder builder) {
  builder.config.replace(action.payload);
}

void _mountState(
    AppState state, Action<AppState> action, AppStateBuilder builder) {
  builder.replace(action.payload);
}

void _setUrl(AppState state, Action<String> action, AppStateBuilder builder) {
  builder.url = fixupUrl(action.payload);
}
