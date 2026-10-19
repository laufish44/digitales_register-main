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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

Homework _entry(HomeworkType type, {String? label}) => Homework(
      (b) => b
        ..id = 4711
        ..type = type
        ..title = type == HomeworkType.homework ? "Erinnerung" : "Schularbeit"
        ..subtitle = "Kapitel 1 bis 3"
        ..label = label
        ..deleted = false
        ..isNew = false
        ..isChanged = false
        ..warning = type == HomeworkType.gradeGroup
        ..checkable = true
        ..checked = false
        ..deleteable = type == HomeworkType.homework
        ..firstSeen = UtcDateTime(2026, 10, 2),
    );

/// The height of the card for [item], with or without the extra buttons.
Future<double> _cardHeight(WidgetTester tester, Homework item,
    {VoidCallback? onEdit, VoidCallback? onAddNote}) async {
  final controller = AutoScrollController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            ItemWidget(
              item: item,
              askWhenDelete: false,
              noInternet: false,
              colorBorder: true,
              colorTestsInRed: true,
              subjectThemes: BuiltMap<String, SubjectTheme>(),
              controller: controller,
              index: 0,
              toggleDone: () {},
              onEdit: onEdit,
              onAddNote: onAddNote,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(Card)).height;
}

void main() {
  testWidgets("the note button does not make a teacher's entry taller",
      (tester) async {
    final exam = _entry(HomeworkType.gradeGroup, label: "Mathematik");
    final before = await _cardHeight(tester, exam);
    final after = await _cardHeight(tester, exam, onAddNote: () {});
    expect(after, before);
    // It sits in the same row as the info button.
    expect(
      tester.getCenter(find.byIcon(Icons.note_add_outlined)).dy,
      tester.getCenter(find.byIcon(Icons.info_outline)).dy,
    );
  });

  testWidgets("the edit button does not make a reminder taller",
      (tester) async {
    final reminder = _entry(HomeworkType.homework);
    final before = await _cardHeight(tester, reminder);
    final after = await _cardHeight(tester, reminder, onEdit: () {});
    expect(after, before);
  });
}
