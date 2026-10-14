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

/// The request behind "krank melden / vorentschuldigen".
///
/// Kept free of Flutter and the store, so the exact body the app sends can be
/// checked against the real register from a plain Dart script.
library;

import 'package:dr/utc_date_time.dart';

/// Where an announcement is posted, relative to `<school>/v2/`.
const futureAbsencePath = "api/student/dashboard/absence_future";

/// Where an announcement is withdrawn; it takes the object the register sent.
const removeFutureAbsencePath = "api/student/dashboard/remove_absence_future";

/// `YYYY-MM-DD`, the format the web app sends.
String absenceDate(UtcDateTime date) =>
    "${date.year.toString().padLeft(4, "0")}-"
    "${date.month.toString().padLeft(2, "0")}-"
    "${date.day.toString().padLeft(2, "0")}";

/// Local midnight of [date] as JSON turns a JavaScript `Date` into it.
String absenceDateObject(UtcDateTime date) =>
    DateTime(date.year, date.month, date.day).toUtc().toIso8601String();

/// The body the web app posts (`saveFutureAbsence`): the picked days both as
/// date objects and as `YYYY-MM-DD`, the lesson numbers, and the reason with
/// its signature. Without the last two the register saves nothing.
Map<String, Object?> futureAbsenceRequest({
  required UtcDateTime startDate,
  required UtcDateTime endDate,
  required int startHour,
  required int endHour,
  required String reason,
  required String signature,
}) =>
    {
      "futureAbsence": <String, Object?>{
        "startDateObject": absenceDateObject(startDate),
        "startTime": startHour,
        "endDateObject": absenceDateObject(endDate),
        "endTime": endHour,
        "reason": reason,
        "reason_signature": signature,
        "startDate": absenceDate(startDate),
        "endDate": absenceDate(endDate),
      },
    };
