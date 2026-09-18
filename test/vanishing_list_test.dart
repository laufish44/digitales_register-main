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

import 'package:dr/widgets/vanishing_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _duration = Duration(milliseconds: 200);

Widget _wrap(List<String> ids) => MaterialApp(
      home: Scaffold(
        body: VanishingList(
          duration: _duration,
          items: [
            for (final id in ids)
              VanishingItem(
                id: id,
                child: SizedBox(height: 40, child: Text(id)),
              ),
          ],
        ),
      ),
    );

void main() {
  testWidgets("shows what it is given", (tester) async {
    await tester.pumpWidget(_wrap(["a", "b", "c"]));
    expect(find.text("a"), findsOneWidget);
    expect(find.text("c"), findsOneWidget);
  });

  testWidgets("a removed row stays on screen while it animates away",
      (tester) async {
    await tester.pumpWidget(_wrap(["a", "b", "c"]));
    await tester.pumpWidget(_wrap(["a", "c"]));

    // Still there: the point of the whole widget is that it does not blink out.
    expect(find.text("b"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text("b"), findsOneWidget);

    await tester.pump(_duration);
    await tester.pump(_duration);
    expect(find.text("b"), findsNothing);
    expect(find.text("a"), findsOneWidget);
    expect(find.text("c"), findsOneWidget);
  });

  testWidgets("the row shrinks to nothing on the way out", (tester) async {
    await tester.pumpWidget(_wrap(["a", "b"]));
    final before = tester.getSize(find.byType(VanishingList)).height;

    await tester.pumpWidget(_wrap(["a"]));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(_duration ~/ 2);
    final during = tester.getSize(find.byType(VanishingList)).height;
    expect(during, lessThan(before), reason: "should be collapsing");

    await tester.pump(_duration);
    await tester.pump(_duration);
    final after = tester.getSize(find.byType(VanishingList)).height;
    expect(after, lessThan(during));
  });

  testWidgets("rows that arrive appear straight away", (tester) async {
    await tester.pumpWidget(_wrap(["a"]));
    await tester.pumpWidget(_wrap(["a", "b"]));
    await tester.pump();
    expect(find.text("b"), findsOneWidget);
  });

  testWidgets("removing everything leaves nothing behind", (tester) async {
    await tester.pumpWidget(_wrap(["a", "b"]));
    await tester.pumpWidget(_wrap(const []));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(_duration);
    await tester.pump(_duration);
    expect(find.text("a"), findsNothing);
    expect(find.text("b"), findsNothing);
  });

  testWidgets("survives being disposed mid-animation", (tester) async {
    await tester.pumpWidget(_wrap(["a", "b"]));
    await tester.pumpWidget(_wrap(["a"]));
    await tester.pump(const Duration(milliseconds: 16));
    // Tear the widget down while the removal is still running; the delayed
    // callback must not touch a dead State.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(_duration);
    await tester.pump(_duration);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a row removed twice in a row does not get stuck",
      (tester) async {
    await tester.pumpWidget(_wrap(["a", "b", "c"]));
    await tester.pumpWidget(_wrap(["a", "c"]));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(_wrap(["a"]));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(_duration);
    await tester.pump(_duration);
    expect(find.text("b"), findsNothing);
    expect(find.text("c"), findsNothing);
    expect(find.text("a"), findsOneWidget);
  });
}
