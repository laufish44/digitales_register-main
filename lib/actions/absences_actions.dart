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
import 'package:built_value/built_value.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';

part 'absences_actions.g.dart';

abstract class AbsencesActions extends ReduxActions {
  factory AbsencesActions() => _$AbsencesActions();
  AbsencesActions._();

  abstract final VoidActionDispatcher load;
  abstract final ActionDispatcher<dynamic> loaded;

  /// Announces an absence in advance ("vorentschuldigen").
  abstract final ActionDispatcher<AddFutureAbsencePayload> addFutureAbsence;

  /// Withdraws an announced absence again.
  abstract final ActionDispatcher<FutureAbsence> removeFutureAbsence;

  /// Hands in the justification for an absence that already happened.
  abstract final ActionDispatcher<JustifyAbsencePayload> justifyAbsence;

  /// Set while a write request is running, so the UI can show a spinner.
  abstract final ActionDispatcher<bool> setSubmitting;
}

abstract class AddFutureAbsencePayload
    implements Built<AddFutureAbsencePayload, AddFutureAbsencePayloadBuilder> {
  factory AddFutureAbsencePayload(
          [void Function(AddFutureAbsencePayloadBuilder)? updates]) =
      _$AddFutureAbsencePayload;
  AddFutureAbsencePayload._();

  UtcDateTime get startDate;
  UtcDateTime get endDate;

  /// Lesson numbers, as shown in the timetable.
  int get startHour;
  int get endHour;

  String? get note;
}

abstract class JustifyAbsencePayload
    implements Built<JustifyAbsencePayload, JustifyAbsencePayloadBuilder> {
  factory JustifyAbsencePayload(
      [void Function(JustifyAbsencePayloadBuilder)? updates]) = _$JustifyAbsencePayload;
  JustifyAbsencePayload._();

  AbsenceGroup get group;

  /// Why the student was absent.
  String get reason;

  /// The name of whoever signs the justification. The server rejects an empty
  /// signature, see `saveAbsence` in the web app.
  String get signature;

  String? get note;

  /// The picked "Selbsterklärung" (e.g. "krank"), or null for a free reason.
  SelfDeclaration? get selfDeclaration;

  /// The extra text some self declarations require.
  String? get selfDeclarationInput;
}
