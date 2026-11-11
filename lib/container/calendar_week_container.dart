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
import 'package:built_value/built_value.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_year.dart' show extraSchoolDay;
import 'package:dr/ui/calendar_week.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Builder;
import 'package:flutter_built_redux/flutter_built_redux.dart';

part 'calendar_week_container.g.dart';

class CalendarWeekContainer extends StatelessWidget {
  final UtcDateTime monday;

  const CalendarWeekContainer({
    super.key,
    required this.monday,
  });
  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, CalendarWeekViewModel>(
      builder: (context, vm, actions) {
        return CalendarWeek(
          vm: vm,
          key: key,
        );
      },
      connect: (state) {
        return CalendarWeekViewModel.fromStateAndWeek(
          state,
          monday,
        );
      },
    );
  }
}

typedef DayCallback = void Function(UtcDateTime day);

abstract class CalendarWeekViewModel
    implements Built<CalendarWeekViewModel, CalendarWeekViewModelBuilder> {
  BuiltList<CalendarDay> get days;
  BuiltMap<String, String> get subjectNicks;
  bool get noInternet;
  CalendarSelection? get selection;
  bool get colorBackground;
  BuiltMap<String, SubjectTheme> get subjectThemes;

  /// When the lessons run, to grey out the ones that are over (#21).
  BuiltList<LessonTime> get lessonTimes;

  factory CalendarWeekViewModel(
          [void Function(CalendarWeekViewModelBuilder)? updates]) =
      _$CalendarWeekViewModel;
  CalendarWeekViewModel._();

  factory CalendarWeekViewModel.fromStateAndWeek(
      AppState state, UtcDateTime monday) {
    final days = state.calendarState.daysForWeek(monday).toList();
    // A Saturday with school is shown even before the register has lessons
    // for it — the register only lists weekends that have some.
    if (days.isNotEmpty) {
      for (var i = 5; i < 7; i++) {
        final date = monday.add(Duration(days: i));
        if (extraSchoolDay(date) != null &&
            !days.any((d) =>
                UtcDateTime(d.date.year, d.date.month, d.date.day) == date)) {
          days.add(CalendarDay((b) => b
            ..date = date
            ..lastFetched = days.first.lastFetched
            ..hours = ListBuilder<CalendarHour>()));
        }
      }
      days.sort((a, b) => a.date.compareTo(b.date));
    }
    return CalendarWeekViewModel(
      (b) => b
        ..days = ListBuilder(days)
        // converting all keys (subject names) to lower case to make accessing cheaper
        ..subjectNicks = MapBuilder(
          state.settingsState.subjectNicks.toMap().map(
                (key, value) => MapEntry(
                  key.toLowerCase(),
                  value,
                ),
              ),
        )
        ..noInternet = state.noInternet
        ..selection = state.calendarState.selection?.toBuilder()
        ..colorBackground = state.settingsState.calendarColorBackground
        ..subjectThemes = state.settingsState.subjectThemes.toBuilder()
        ..lessonTimes = ListBuilder(
            LessonTimes.resolve(state.settingsState.lessonSchedule)),
    );
  }
}
