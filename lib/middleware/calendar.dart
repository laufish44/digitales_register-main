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

part of 'middleware.dart';

// `schoolYearStart` and `now` come from school_year.dart / util.dart, both
// already imported by middleware.dart.

final _calendarMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(CalendarActionsNames.load, _loadCalendar)
      ..add(CalendarActionsNames.select, _selectionChanged)
      ..add(CalendarActionsNames.setCurrentMonday, _weekChanged)
      ..add(CalendarActionsNames.onOpenFile, _openSubmission)
      ..add(CalendarActionsNames.onSaveFileAs, _saveSubmissionAs)
      ..add(CalendarActionsNames.onCopyFile, _copySubmission)
      ..add(RoutingActionsNames.showCalendar, _clearSelection);

Future<void> _loadCalendar(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<UtcDateTime> action) async {
  if (api.state.noInternet) return;

  await next(action);
  final dynamic data = await wrapper.send("api/calendar/student",
      args: {"startDate": DateFormat("yyyy-MM-dd").format(action.payload)});

  if (data != null) {
    await api.actions.calendarActions.loaded(data as Map<String, dynamic>);
  }
}

/// Weeks already asked for in this session, so a second call is cheap.
final _prefetchedWeeks = <UtcDateTime>{};

@visibleForTesting
void resetCalendarPrefetchState() => _prefetchedWeeks.clear();

/// How long to wait between weeks.
///
/// Forty requests in a row would be rude to the school's server and would
/// compete with whatever the user is actually looking at.
const _prefetchPause = Duration(milliseconds: 250);

/// Fetches the whole school year's calendar in the background.
///
/// Without this the calendar only ever holds the weeks the user paged through,
/// which left the search, the statistics and "which subject did I miss" with
/// gaps that were impossible to explain — the app would say "open the calendar
/// first", which is not an answer.
///
/// Runs once per session, one week at a time, and gives up quietly on any
/// failure: this is a convenience, and every page still loads its own week.
Future<void> prefetchWholeCalendar(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) async {
  if (!api.state.settingsState.prefetchWholeCalendar) return;
  if (api.state.noInternet || !api.state.loginState.loggedIn) return;

  final settings = api.state.settingsState;
  // From the start of the school year to its last day, so the statistics cover
  // the whole year rather than just what is ahead.
  final from = toMonday(UtcDateTime(schoolYearStart(now), 9, 1));
  final until = settings.lastSchoolDay ?? now.add(const Duration(days: 120));

  var monday = from;
  var fetched = 0;
  while (!monday.isAfter(until)) {
    if (!api.state.loginState.loggedIn) return;
    if (_prefetchedWeeks.add(monday)) {
      try {
        await api.actions.calendarActions.load(monday);
        fetched++;
      } catch (e) {
        log("calendar prefetch failed for $monday", error: e);
      }
      if (api.state.noInternet) return;
      await Future<void>.delayed(_prefetchPause);
    }
    monday = monday.add(const Duration(days: 7));
  }
  log("calendar prefetch done, $fetched weeks fetched");
}

Future<void> _selectionChanged(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<CalendarSelection?> action) async {
  await next(action);
  if (action.payload == null) {
    return;
  }
  final newWeek = toMonday(action.payload!.date);
  if (api.state.calendarState.currentMonday != newWeek) {
    await api.actions.calendarActions.setCurrentMonday(newWeek);
    await api.actions.calendarActions.load(newWeek);
  }
}

Future<void> _weekChanged(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<UtcDateTime> action) async {
  await next(action);
  final selectedDate = api.state.calendarState.selection?.date;
  if (selectedDate != null && toMonday(selectedDate) != action.payload) {
    await api.actions.calendarActions.select(
      CalendarSelection(
        (b) => b
          ..date = UtcDateTime(
            action.payload.year,
            action.payload.month,
            action.payload.day,
          ),
      ),
    );
  }
}

Future<void> _clearSelection(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  await api.actions.calendarActions.select(null);
}

/// Makes sure the attachment is on disk, downloading it if it is not.
Future<bool> _ensureSubmission(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  LessonContentSubmission submission,
) async {
  if (submission.fileAvailable && await canOpenFile(submission.uniqueName)) {
    return true;
  }

  await api.actions.calendarActions.onDownloadFile(submission);
  final success = await downloadFile(
    "${wrapper.baseAddress}api/lessonContent/lessonContentSubmissionDownloadEntry",
    submission.uniqueName,
    <String, dynamic>{
      "parentId": submission.lessonContentId,
      "submissionId": submission.id,
    },
  );
  await api.actions.calendarActions.fileAvailable(
    submission.rebuild((b) => b..fileAvailable = success),
  );
  return success;
}

Future<void> _openSubmission(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<LessonContentSubmission> action) async {
  await next(action);
  if (!await _ensureSubmission(api, action.payload)) return;
  await openFile(action.payload.uniqueName);
}

Future<void> _saveSubmissionAs(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<LessonContentSubmission> action) async {
  await next(action);
  if (!await _ensureSubmission(api, action.payload)) return;
  await saveAttachmentAs(
    action.payload.uniqueName,
    suggestedName: action.payload.originalName,
  );
}

Future<void> _copySubmission(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<LessonContentSubmission> action) async {
  await next(action);
  if (!await _ensureSubmission(api, action.payload)) return;
  await copyAttachmentToClipboard(action.payload.uniqueName);
}
