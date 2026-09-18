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

/// Puts the dashboard cards on screen.
///
/// Besides rendering, this is where the data the cards need is fetched: the
/// dashboard itself is always loaded, but the calendar, the grades, the
/// absences and the messages are only fetched when their page is opened. A card
/// that shows them therefore asks for them once, when it first appears.
library;

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart' as util;
import 'package:dr/widgets/dashboard_widgets.dart';
import 'package:dr/widgets/widget_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class DashboardWidgetsContainer extends StatelessWidget {
  const DashboardWidgetsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, _WidgetBoardViewModel>(
      connect: (state) => _WidgetBoardViewModel(state),
      builder: (context, vm, actions) => _WidgetBoard(vm: vm, actions: actions),
    );
  }
}

class _WidgetBoardViewModel {
  factory _WidgetBoardViewModel(AppState state) {
    final settings = state.settingsState;
    final enabled = [
      for (final config in settings.dashboardWidgets)
        if (config.enabled && dashboardWidgetTypeById(config.type) != null)
          config,
    ];
    return _WidgetBoardViewModel._(
      configs: enabled,
      data: DashboardWidgetData(
        now: util.now,
        calendar: state.calendarState,
        dashboard: state.dashboardState,
        absences: state.absencesState,
        grades: state.gradesState,
        messages: state.messagesState,
        holidays: settings.holidays.toList(),
        lastSchoolDay: settings.lastSchoolDay,
        absenceLimitPercentage: settings.absenceWarningThreshold,
        weeklyLessons: settings.weeklyLessons,
        lessonTimes: LessonTimes.resolve(
          configured: settings.lessonTimes,
          calendar: state.calendarState,
          preferServer: settings.lessonTimesFromServer,
        ),
      ),
      loggedIn: state.loginState.loggedIn,
      hasAbsences: state.absencesState.statistic != null,
      hasGrades: state.gradesState.subjects.isNotEmpty,
      hasMessages: state.messagesState.lastFetched != null,
      hasCalendar: state.calendarState.days.isNotEmpty,
      semester: state.gradesState.semester,
    );
  }

  const _WidgetBoardViewModel._({
    required this.configs,
    required this.data,
    required this.loggedIn,
    required this.hasAbsences,
    required this.hasGrades,
    required this.hasMessages,
    required this.hasCalendar,
    required this.semester,
  });

  final List<DashboardWidgetConfig> configs;
  final DashboardWidgetData data;
  final bool loggedIn, hasAbsences, hasGrades, hasMessages, hasCalendar;
  final Semester semester;

  bool needs(String widgetId) => configs.any((c) => c.type == widgetId);

  bool get needsLessons =>
      configs.any((c) => c.includeLessons && _looksAtLessons(c.type));

  static bool _looksAtLessons(String type) =>
      type == todayWidgetId || type == tomorrowWidgetId;

  /// Compared field by field because [DashboardWidgetData] holds plain lists;
  /// the built_value states inside it compare by value on their own.
  @override
  bool operator ==(Object other) =>
      other is _WidgetBoardViewModel &&
      other.loggedIn == loggedIn &&
      other.hasAbsences == hasAbsences &&
      other.hasGrades == hasGrades &&
      other.hasMessages == hasMessages &&
      other.hasCalendar == hasCalendar &&
      other.semester == semester &&
      _sameConfigs(other.configs, configs) &&
      other.data.calendar == data.calendar &&
      other.data.dashboard == data.dashboard &&
      other.data.absences == data.absences &&
      other.data.grades == data.grades &&
      other.data.messages == data.messages &&
      other.data.lastSchoolDay == data.lastSchoolDay &&
      other.data.absenceLimitPercentage == data.absenceLimitPercentage &&
      other.data.weeklyLessons == data.weeklyLessons &&
      BuiltList(other.data.holidays) == BuiltList(data.holidays);

  static bool _sameConfigs(
      List<DashboardWidgetConfig> a, List<DashboardWidgetConfig> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        loggedIn,
        hasAbsences,
        hasGrades,
        hasMessages,
        hasCalendar,
        semester,
        Object.hashAll(configs),
        data.calendar,
        data.dashboard,
        data.absences,
        data.grades,
        data.messages,
      );
}

class _WidgetBoard extends StatefulWidget {
  const _WidgetBoard({required this.vm, required this.actions});

  final _WidgetBoardViewModel vm;
  final AppActions actions;

  @override
  State<_WidgetBoard> createState() => _WidgetBoardState();
}

class _WidgetBoardState extends State<_WidgetBoard> {
  /// What has already been asked for, so a rebuild does not fetch again.
  final _requested = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchWhatIsMissing());
  }

  @override
  void didUpdateWidget(_WidgetBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A card that was switched on in the settings needs its data too.
    _fetchWhatIsMissing();
  }

  void _fetchWhatIsMissing() {
    final vm = widget.vm;
    if (!vm.loggedIn || !mounted) return;

    if (vm.needs(absencesWidgetId) &&
        !vm.hasAbsences &&
        _requested.add(absencesWidgetId)) {
      widget.actions.absencesActions.load();
    }
    if (vm.needs(gradesWidgetId) &&
        !vm.hasGrades &&
        _requested.add(gradesWidgetId)) {
      widget.actions.gradesActions.load(vm.semester);
    }
    if (vm.needs(messagesWidgetId) &&
        !vm.hasMessages &&
        _requested.add(messagesWidgetId)) {
      widget.actions.messagesActions.load();
    }
    // The calendar is only needed for the lesson chips; everything else the
    // cards show is already in the dashboard response.
    if (vm.needsLessons && _requested.add("calendar")) {
      widget.actions.calendarActions.load(util.toMonday(util.now));
    }
  }

  void _openCalendarAt(UtcDateTime date) {
    widget.actions.routingActions.showCalendar();
    widget.actions.calendarActions.setCurrentMonday(util.toMonday(date));
    widget.actions.calendarActions.load(util.toMonday(date));
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    if (vm.configs.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final config in vm.configs)
          buildDashboardWidget(
            config: config,
            data: vm.data,
            onOpenCalendar: () => _openCalendarAt(util.now),
            onOpenAbsences: widget.actions.routingActions.showAbsences.call,
            onOpenGrades: widget.actions.routingActions.showGrades.call,
            onOpenMessages: widget.actions.routingActions.showMessages.call,
          ),
      ],
    );
  }
}
