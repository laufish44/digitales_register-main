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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/stats.dart';
import 'package:dr/ui/calendar_card.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class CalendarCardContainer extends StatelessWidget {
  final int hourIndex;
  final UtcDateTime day;

  const CalendarCardContainer({
    super.key,
    required this.hourIndex,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, CalendarCardViewModel>(
      builder: (context, state, actions) {
        return CalendarCard(
          hour: state.hour,
          theme: state.theme,
          selected: state.selected,
          onOpenFile: actions.calendarActions.onOpenFile.call,
          noInternet: state.noInternet,
          absenceMark: state.absenceMark,
        );
      },
      connect: (state) {
        final hour = state.calendarState.days[day]!.hours[hourIndex];
        return CalendarCardViewModel(
          hour: hour,
          theme: state.settingsState.subjectThemes[hour.subject]!,
          selected: state.calendarState.selection?.date == day &&
              state.calendarState.selection?.hour == hour.fromHour,
          noInternet: state.noInternet,
          absenceMark: state.settingsState.markAbsencesInCalendar
              ? AbsenceMarks.forRange(
                  date: day,
                  fromHour: hour.fromHour,
                  toHour: hour.toHour,
                  absences: state.absencesState.absences,
                  futureAbsences: state.absencesState.futureAbsences,
                )
              : AbsenceMark.none,
        );
      },
    );
  }
}

class CalendarCardViewModel {
  final CalendarHour hour;
  final SubjectTheme theme;
  final bool selected;
  final bool noInternet;
  final AbsenceMark absenceMark;

  CalendarCardViewModel({
    required this.noInternet,
    required this.hour,
    required this.theme,
    required this.selected,
    required this.absenceMark,
  });

  @override
  bool operator ==(Object other) =>
      other is CalendarCardViewModel &&
      other.hour == hour &&
      other.theme == theme &&
      other.selected == selected &&
      other.noInternet == noInternet &&
      other.absenceMark == absenceMark;

  @override
  int get hashCode =>
      Object.hash(hour, theme, selected, noInternet, absenceMark);
}
