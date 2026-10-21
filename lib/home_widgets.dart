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

/// The data behind the Android home screen widgets.
///
/// The widgets are drawn by Android (`HomeWidgets.kt`), not by Flutter: a home
/// screen widget has to be there while the app is closed. So whenever the
/// app's data changes, a snapshot of what the widgets show goes to Android as
/// one JSON document, and Android draws from it until the next one.
///
/// Anything that depends on today — "in 3 Tagen", which day is "Heute", the
/// next lesson, holiday countdowns — is left to Android and computed when
/// drawing, from the dates in the snapshot. A snapshot taken in the evening
/// must still be right the next morning.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_year.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart' as util;
import 'package:dr/util.dart' show gradeAverageFormat;
import 'package:dr/widgets/dashboard_widgets.dart';
import 'package:flutter/services.dart';

/// Bumped when the shape of the snapshot changes in a way the Android side
/// has to know about.
const homeWidgetSnapshotVersion = 1;

/// How many days ahead the per-day lists reach.
const _daysAhead = 21;

String _dayKey(UtcDateTime d) => "${d.year.toString().padLeft(4, "0")}-"
    "${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

String _format(double scaledByHundred) =>
    gradeAverageFormat.format(scaledByHundred / 100);

Map<String, Object?> _entry(UpcomingExam e) => {
      "t": e.name,
      "s": [e.subject, e.typeName].where((s) => s.isNotEmpty).join(" · "),
      "k": e.isExam
          ? "exam"
          : e.isReminder
              ? "reminder"
              : "homework",
    };

/// Everything the widgets show, as plain JSON values.
Map<String, Object?> homeWidgetSnapshot(
  DashboardWidgetData data, {
  required bool loggedIn,
}) {
  final now = data.now;
  final today = UtcDateTime(now.year, now.month, now.day);

  final days = <String, Object?>{};
  for (var i = 0; i < _daysAhead; i++) {
    final day = today.add(Duration(days: i));
    final entries = Agenda.forDay(
      calendar: data.calendar,
      dashboard: data.dashboard,
      day: day,
    );
    final lessons = Agenda.lessonsOn(data.calendar, day);
    if (entries.isEmpty && lessons.isEmpty) continue;
    days[_dayKey(day)] = {
      "entries": [for (final e in entries) _entry(e)],
      "lessons": [
        for (final lesson in lessons)
          {
            "h": lesson.fromHour == lesson.toHour
                ? "${lesson.fromHour}."
                : "${lesson.fromHour}.–${lesson.toHour}.",
            "t": lesson.subject,
            "r": lesson.rooms.join(", "),
            "from": LessonTimes.forHour(data.lessonTimes, lesson.fromHour)
                ?.startLabel,
            "to":
                LessonTimes.forHour(data.lessonTimes, lesson.toHour)?.endLabel,
          },
      ],
    };
  }

  final upcoming = ExamCountdown.upcoming(
    data.calendar,
    dashboard: data.dashboard,
    now: now,
    within: const Duration(days: 60),
    includeHomework: true,
  );

  return {
    "v": homeWidgetSnapshotVersion,
    "loggedIn": loggedIn,
    "generated": DateTime.now().toIso8601String(),
    "days": days,
    "upcoming": [
      for (final e in upcoming.take(40))
        {..._entry(e), "d": _dayKey(e.deadline)},
    ],
    "grades": _grades(data),
    "absences": _absences(data, today),
    "holidays": [
      for (final h in data.holidays)
        {"t": h.name, "from": _dayKey(h.start), "to": _dayKey(h.end)},
    ],
    "lastSchoolDay":
        data.lastSchoolDay == null ? null : _dayKey(data.lastSchoolDay!),
    "messages": _messages(data),
  };
}

Map<String, Object?>? _grades(DashboardWidgetData data) {
  final semester = data.grades.semester;
  final perSubject = <Map<String, Object?>>[];
  final recent = <MapEntry<String, GradeAll>>[];
  final everything = <GradeAll>[];
  for (final subject in data.grades.subjects) {
    final grades = subject.basicGrades(semester) ?? const <GradeAll>[];
    everything.addAll(grades);
    for (final grade in grades) {
      if (!grade.cancelled && grade.grade != null) {
        recent.add(MapEntry(subject.name, grade));
      }
    }
    final average = GradeStats.subjectAverage(grades);
    if (average != null) {
      perSubject.add({
        "t": subject.name,
        "v": _format(average),
        "n": average,
        "low": average < 600,
      });
    }
  }
  if (perSubject.isEmpty) return null;
  perSubject.sort((a, b) => (a["n"]! as double).compareTo(b["n"]! as double));
  recent.sort((a, b) => b.value.date.compareTo(a.value.date));

  final overall = GradeStats.overallAverage(
    data.grades.subjects,
    semester,
    ignored: data.ignoredForAverage,
  );
  final trend = GradeStats.trendPerMonth(everything);
  return {
    "overall": overall == null ? null : _format(overall),
    "overallLow": overall != null && overall < 600,
    "trend": trend == null
        ? null
        : "${trend >= 0 ? "+" : ""}${gradeAverageFormat.format(trend)}",
    "subjects": [
      for (final s in perSubject) {"t": s["t"], "v": s["v"], "low": s["low"]},
    ],
    "recent": [
      for (final entry in recent.take(12))
        {
          "t": entry.key,
          "s": entry.value.type,
          "v": formatGradeFromInt(entry.value.grade),
          "d": _dayKey(entry.value.date),
          "low": entry.value.grade! < 600,
        },
    ],
  };
}

Map<String, Object?>? _absences(DashboardWidgetData data, UtcDateTime today) {
  final statistic = data.absences.statistic;
  if (statistic == null) return null;
  final absences = data.absences.absences;
  final limit = data.absenceLimitPercentage.toDouble();
  final year = AbsenceStats.yearBudget(
    absences: absences,
    calendar: data.calendar,
    now: today,
    limitPercentage: limit,
    schoolDays: schoolDaysOfYear(
      today,
      holidays: data.holidays,
      lastSchoolDay: data.lastSchoolDay,
    ),
  );
  final budget = year == null
      ? AbsenceStats.budget(
          statistic: statistic, absences: absences, limitPercentage: limit)
      : null;
  final remaining = year?.remainingLessons ?? budget?.remainingLessons;
  final percentage = AbsenceStats.missedPercentage(statistic);
  return {
    "percent":
        percentage == null ? null : gradeAverageFormat.format(percentage),
    "overLimit": percentage != null && percentage >= limit,
    "limit": data.absenceLimitPercentage,
    "missed": AbsenceStats.missedLessons(absences).round(),
    "remaining": remaining?.floor(),
    "open": AbsenceStats.notYetJustifiedCount(absences),
    "delayed": statistic.delayed,
  };
}

Map<String, Object?> _messages(DashboardWidgetData data) {
  final unread = data.messages.messages.where((m) => m.isNew).toList()
    ..sort((a, b) => -a.timeSent.compareTo(b.timeSent));
  return {
    "loaded": data.messages.lastFetched != null,
    "unread": unread.length,
    "items": [
      for (final m in unread.take(8)) {"t": m.subject, "s": m.fromName},
    ],
  };
}

/// The snapshot for the current [state].
Map<String, Object?> homeWidgetSnapshotOf(AppState state) {
  final settings = state.settingsState;
  return homeWidgetSnapshot(
    DashboardWidgetData(
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
      lessonTimes: LessonTimes.resolve(settings.lessonSchedule),
      ignoredForAverage: settings.ignoreForGradesAverage.toList(),
    ),
    loggedIn: state.loginState.loggedIn,
  );
}

const _channel = MethodChannel("it.digitalesregisterapp/home_widgets");

/// Sends snapshots to Android, at most one every few seconds and only when
/// something changed — loading the app fires dozens of actions in a row.
class HomeWidgetPublisher {
  HomeWidgetPublisher._();

  static final instance = HomeWidgetPublisher._();

  Timer? _pending;
  String? _lastSent;
  AppState? _latest;

  void schedule(AppState state) {
    _latest = state;
    _pending ??= Timer(const Duration(seconds: 2), _flush);
  }

  Future<void> _flush() async {
    _pending = null;
    final state = _latest;
    if (state == null) return;
    final String encoded;
    try {
      encoded = json.encode(homeWidgetSnapshotOf(state));
    } catch (e, trace) {
      log("could not build the home widget snapshot",
          error: e, stackTrace: trace);
      return;
    }
    if (encoded == _lastSent) return;
    try {
      await _channel.invokeMethod<void>("update", encoded);
      _lastSent = encoded;
    } on PlatformException catch (e) {
      log("could not update the home widgets", error: e);
    } on MissingPluginException {
      // Not registered (tests, other platforms).
    }
  }
}

/// Keeps the home screen widgets in step with the app's data.
NextActionHandler homeWidgetsMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          await next(action);
          if (Platform.isAndroid) {
            HomeWidgetPublisher.instance.schedule(api.state);
          }
        };
