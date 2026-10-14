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

final _absencesMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(AbsencesActionsNames.load, _loadAbsences)
      ..add(AbsencesActionsNames.addFutureAbsence, _addFutureAbsence)
      ..add(AbsencesActionsNames.removeFutureAbsence, _removeFutureAbsence)
      ..add(AbsencesActionsNames.justifyAbsence, _justifyAbsence);

Future<void> _loadAbsences(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  if (api.state.noInternet) return;
  await next(action);
  final dynamic response = await wrapper.send("api/student/dashboard/absences");
  if (response != null) {
    await api.actions.absencesActions.loaded(response);
  }
}

/// `YYYY-MM-DD`, the format the web app sends.
String _absenceDate(UtcDateTime date) =>
    "${date.year.toString().padLeft(4, "0")}-"
    "${date.month.toString().padLeft(2, "0")}-"
    "${date.day.toString().padLeft(2, "0")}";

/// Local midnight of [date] as JSON turns a JavaScript `Date` into it.
String _absenceDateObject(UtcDateTime date) =>
    DateTime(date.year, date.month, date.day).toUtc().toIso8601String();

/// The message of an error the server answered with instead of failing the
/// request, or null when there is none.
String? _serverError(dynamic response) {
  final map = getMap(response);
  if (map == null || map["error"] == null) return null;
  final message = getString(map["message"]);
  return message == null || message.isEmpty ? "${map["error"]}" : message;
}

Future<void> _addFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<AddFutureAbsencePayload> action) async {
  await next(action);
  if (_blockWriteInDemo(api)) return;

  final payload = action.payload;
  await api.actions.absencesActions.setSubmitting(true);
  try {
    // The same object the web app posts (`saveFutureAbsence`): the picked days
    // both as date objects and as `YYYY-MM-DD`, the lesson numbers, and the
    // reason with its signature. Without the last two nothing gets saved.
    final dynamic response = await wrapper.send(
      "api/student/dashboard/absence_future",
      args: {
        "futureAbsence": <String, Object?>{
          "startDateObject": _absenceDateObject(payload.startDate),
          "startTime": payload.startHour,
          "endDateObject": _absenceDateObject(payload.endDate),
          "endTime": payload.endHour,
          "reason": payload.reason,
          "reason_signature": payload.signature,
          "startDate": _absenceDate(payload.startDate),
          "endDate": _absenceDate(payload.endDate),
        },
      },
    );
    final error = _serverError(response);
    if (response == null || error != null) {
      showSnackBar(error == null
          ? "Die Absenz konnte nicht eingetragen werden"
          : "Die Absenz konnte nicht eingetragen werden: $error");
      return;
    }
    showSnackBar("Absenz vorentschuldigt");
    await api.actions.absencesActions.load();
  } finally {
    await api.actions.absencesActions.setSubmitting(false);
  }
}

Future<void> _removeFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<FutureAbsence> action) async {
  await next(action);
  if (_blockWriteInDemo(api)) return;

  final raw = action.payload.raw;
  if (raw == null) {
    // Loaded by an older version of the app that did not keep the original
    // json; a refresh brings it back with the raw data attached.
    showSnackBar("Bitte lade die Absenzen neu und versuche es noch einmal");
    await api.actions.absencesActions.load();
    return;
  }

  await api.actions.absencesActions.setSubmitting(true);
  try {
    final dynamic response = await wrapper.send(
      "api/student/dashboard/remove_absence_future",
      args: {"futureAbsence": json.decode(raw)},
    );
    final error = _serverError(response);
    if (response == null || error != null) {
      showSnackBar(error == null
          ? "Die Absenz konnte nicht entfernt werden"
          : "Die Absenz konnte nicht entfernt werden: $error");
      return;
    }
    showSnackBar("Vorentschuldigung entfernt");
    await api.actions.absencesActions.load();
  } finally {
    await api.actions.absencesActions.setSubmitting(false);
  }
}

Future<void> _justifyAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<JustifyAbsencePayload> action) async {
  await next(action);
  if (_blockWriteInDemo(api)) return;

  final payload = action.payload;
  final raw = payload.group.raw;
  if (raw == null) {
    showSnackBar("Bitte lade die Absenzen neu und versuche es noch einmal");
    await api.actions.absencesActions.load();
    return;
  }

  // Hand the group back the way the server sent it, with only the
  // justification fields filled in - that is what the web app does.
  final group = getMap(json.decode(raw))!.cast<String, Object?>();
  group["reason"] = payload.reason;
  group["reason_signature"] = payload.signature;
  group["reason_timestamp"] = DateTime.now().toIso8601String();
  if (payload.note != null) group["note"] = payload.note;

  // A "Selbsterklärung" is the ready-made reason the school offers (this is
  // what the website's "krank melden" uses). The web app sends both the id and
  // the whole item, and the "none" values when nothing was picked.
  final declaration = payload.selfDeclaration;
  if (declaration != null && declaration.id > 0) {
    group["selfdecl_id"] = declaration.id;
    group["selfdecl_item"] = <String, Object?>{
      "id": declaration.id,
      "title": declaration.title,
      "text": declaration.text,
      "inputmandatory": declaration.inputMandatory,
      "inputexplain": declaration.inputExplain,
    };
  } else {
    group["selfdecl_id"] = 0;
    group["selfdecl_item"] = null;
  }
  group["selfdecl_input"] = payload.selfDeclarationInput ?? "";

  await api.actions.absencesActions.setSubmitting(true);
  try {
    final dynamic response = await wrapper.send(
      "api/student/dashboard/absence_reason",
      args: {"absenceGroup": group},
    );
    final error = _serverError(response);
    if (response == null || error != null) {
      showSnackBar(error == null
          ? "Die Entschuldigung konnte nicht gespeichert werden"
          : "Die Entschuldigung konnte nicht gespeichert werden: $error");
      return;
    }
    showSnackBar("Entschuldigung gespeichert");
    await api.actions.absencesActions.load();
  } finally {
    await api.actions.absencesActions.setSubmitting(false);
  }
}

/// Write requests must never reach a real server from the demo account.
bool _blockWriteInDemo(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) {
  if (api.state.isDemo) {
    showSnackBar("Im Demo-Modus nicht verfügbar");
    return true;
  }
  return false;
}
