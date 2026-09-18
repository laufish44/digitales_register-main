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

Future<void> _addFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<AddFutureAbsencePayload> action) async {
  await next(action);
  if (_blockWriteInDemo(api)) return;

  final payload = action.payload;
  await api.actions.absencesActions.setSubmitting(true);
  try {
    final dynamic response = await wrapper.send(
      "api/student/dashboard/absence_future",
      args: {
        "futureAbsence": <String, Object?>{
          "startDate": _absenceDate(payload.startDate),
          "endDate": _absenceDate(payload.endDate),
          "startTime": payload.startHour,
          "endTime": payload.endHour,
          if (payload.note != null) "note": payload.note,
        },
      },
    );
    if (response == null) {
      showSnackBar("Die Absenz konnte nicht eingetragen werden");
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
    if (response == null) {
      showSnackBar("Die Absenz konnte nicht entfernt werden");
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
    if (response == null) {
      showSnackBar("Die Entschuldigung konnte nicht gespeichert werden");
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
