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

import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';

import 'package:dr/actions/absences_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

final absencesReducerBuilder = NestedReducerBuilder<AppState, AppStateBuilder,
    AbsencesState, AbsencesStateBuilder>(
  (s) => s.absencesState,
  (b) => b.absencesState,
)
  ..add<dynamic>(AbsencesActionsNames.loaded, _loaded)
  ..add(AbsencesActionsNames.setSubmitting, _setSubmitting);

void _loaded(
    AbsencesState state, Action<dynamic> action, AbsencesStateBuilder builder) {
  final submitting = state.submitting;
  builder.replace(tryParse(getMap(action.payload)!, _parseAbsences));
  // _parseAbsences builds a fresh state; keep the in-flight flag.
  builder.submitting = submitting;
}

@visibleForTesting
AbsencesState parseAbsencesResponse(Map json) => _parseAbsences(json);

void _setSubmitting(
    AbsencesState state, Action<bool> action, AbsencesStateBuilder builder) {
  builder.submitting = action.payload;
}

AbsencesState _parseAbsences(Map json) {
  final rawStats = getMap(json["statistics"])!;
  final stats = AbsenceStatisticBuilder()
    ..counter = getInt(rawStats["counter"])
    ..counterForSchool = getInt(rawStats["counterForSchool"])
    ..delayed = getInt(rawStats["delayed"])
    ..justified = getInt(rawStats["justified"])
    ..notJustified = getInt(rawStats["notJustified"])
    ..percentage = rawStats["percentage"]?.toString().isNotEmpty == true
        ? rawStats["percentage"].toString()
        : null;
  final absences = (json["absences"] as List).map(_parseAbsence);
  final futureAbsences =
      (json["futureAbsences"] as List).map(_parseFutureAbsence);
  // Prefer the list of currently active reasons; older servers only send the
  // full list.
  final declarations = getList(json["selfDeclarationsActiveList"]) ??
      getList(json["selfDeclarationsList"]) ??
      const <dynamic>[];
  return AbsencesState(
    (b) => b
      ..statistic = stats
      ..absences = ListBuilder(absences)
      ..futureAbsences = ListBuilder(futureAbsences)
      ..selfDeclarations =
          ListBuilder(declarations.map(_parseSelfDeclaration))
      ..canEdit = getBool(json["canEdit"]) ?? true
      ..selfDeclarationActive =
          getBool(json["isAbsencesSelfDeclarationActive"]) ?? false
      ..selfDeclarationMandatory =
          getBool(json["isAbsencesSelfDeclarationMandatory"]) ?? false
      ..lastFetched = UtcDateTime.now(),
  );
}

SelfDeclaration _parseSelfDeclaration(dynamic d) {
  return SelfDeclaration(
    (b) => b
      ..id = getInt(d["id"]) ?? 0
      ..title = getString(d["title"]) ?? ""
      ..text = getString(d["text"]) ?? ""
      ..inputMandatory = getBool(d["inputmandatory"]) ?? false
      ..inputExplain = getString(d["inputexplain"]) ?? "",
  );
}

AbsenceGroup _parseAbsence(dynamic g) {
  return AbsenceGroup(
    (b) => b
      ..raw = json.encode(g)
      ..justified = AbsenceJustified.fromInt(getInt(g["justified"])!)
      ..reasonSignature = getString(g["reason_signature"])
      ..reasonTimestamp = g["reason_timestamp"] is String
          ? UtcDateTime.tryParse(g["reason_timestamp"] as String)
          : null
      ..reason = getString(g["reason"])
      ..note = getString(g["note"])
      ..absences = ListBuilder(
        (g["group"] as List).map<Absence>(
          (dynamic a) {
            return Absence(
              (b) => b
                ..minutes = getInt(a["minutes"])
                ..date = UtcDateTime.parse(getString(a["date"])!)
                ..hour = getInt(a["hour"])
                ..minutesCameTooLate = getInt(a["minutes_begin"])
                ..minutesLeftTooEarly = getInt(a["minutes_end"]),
            );
          },
        ),
      )
      ..minutes = b.absences.build().fold<int>(0, (min, a) {
        if (a.minutes != 50) {
          min += a.minutesCameTooLate + a.minutesLeftTooEarly;
        }
        return min;
      })
      ..hours = b.absences.build().fold<int>(0, (h, a) {
        if (a.minutes == 50) {
          h++;
        }
        return h;
      }),
  );
}

FutureAbsence _parseFutureAbsence(dynamic absence) {
  return FutureAbsence(
    (b) => b
      ..raw = json.encode(absence)
      ..note = getString(absence["note"])
      ..startDate = UtcDateTime.parse(getString(absence["startDate"])!)
      ..endDate = UtcDateTime.parse(getString(absence["endDate"])!)
      ..startHour = getInt(absence["startTime"])
      ..endHour = getInt(absence["endTime"])
      ..justified = AbsenceJustified.fromInt(getInt(absence["justified"])!)
      ..reason = getString(absence["reason"])
      ..reasonSignature = getString(absence["reason_signature"])
      ..reasonTimestamp = absence["reason_timestamp"] is String
          ? UtcDateTime.tryParse(absence["reason_timestamp"] as String)
          : null,
  );
}
