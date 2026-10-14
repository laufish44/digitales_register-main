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

import 'package:dr/lesson_times.dart';
import 'package:dr/ui/absence_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The website starts an announcement for today with the lesson that is
  // running, or the next one; once the day is over, it moves to tomorrow.
  group("first lesson of an announcement for today", () {
    final times = defaultLessonTimes;
    DateTime at(int hour, int minute) => DateTime(2026, 10, 14, hour, minute);

    test("is the first lesson before school", () {
      expect(firstLessonLeftToday(times, at(7, 30)), 1);
    });

    test("is the lesson running right now", () {
      // 3rd lesson: 9:45-10:35.
      expect(firstLessonLeftToday(times, at(10, 0)), 3);
    });

    test("is the next lesson during a break", () {
      // Between the 4th (until 11:25) and the 5th (from 11:40).
      expect(firstLessonLeftToday(times, at(11, 30)), 5);
    });

    test("is nothing once the day is over", () {
      expect(firstLessonLeftToday(times, at(18, 0)), isNull);
    });
  });
}
