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

import 'package:dr/ui/simple_markdown.dart';
import 'package:dr/ui/update_dialog.dart';
import 'package:dr/update/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The notes of the 8.6.0 release, as GitHub delivers them.
const _releaseNotes = r'''
Krank melden funktioniert, der Notendurchschnitt stimmt mit der Notenübersicht überein, und der Schulkalender 2026/27 ist eingebaut.

## Krank melden / vorentschuldigen

Das Register verlangt eine **Begründung** und eine **Bestätigung** (Vor- und Nachname). Einträge ohne die beiden hat es stillschweigend verworfen, deshalb kam bisher nichts an. Beide Felder sind jetzt im Dialog:

* Die Bestätigung ist mit deinem Namen vorausgefüllt.
* Für die Begründung gibt es Schnellauswahlen („Krankheit“, „Arzttermin“, „Familiäre Gründe“).
* Die Stunden sind vorbelegt wie auf der Website: ab der laufenden (oder nächsten) Stunde bis Schulschluss; nach Schulschluss für morgen.

## Notendurchschnitt

Statistik und Noten-Widget rechnen jetzt wie die Notenübersicht und die Original-App: **Durchschnitt der Fächerschnitte**, ohne die in den Einstellungen ausgeschlossenen Fächer. Vorher wurden dort alle Noten in einen Topf geworfen. Ein Fach mit zehn Noten zählte dann zehnmal so viel wie eines mit einer, und es kam ein anderer Wert heraus. Die Statistik zeigt diesen zweiten Wert weiterhin, klar beschriftet als „Schnitt aller Noten“.

## Schulkalender 2026/27

Schulbeginn 7.9.2026, Schulende 16.6.2027, alle Ferien und schulfreien Tage, **175 Schultage**. Ein Test zählt sie gegen die Summen auf dem Kalenderblatt (Mo 34, Di 35, Mi 36, Do 35, Fr 35). Daraus rechnen jetzt:

* das **Absenz-Budget**, auf der Absenzenseite und in der Statistik mit derselben Zahl: Stunden bis zum Schulende statt bisher geschätzt,
* der **Ferien-Countdown** in der Seitenleiste,
* das Laden des ganzen Kalenders beim Anmelden.

Gespeicherte Ferien aus der Vorversion werden einmal durch den Schulkalender ersetzt.

## Neu

* **Semester pro Schuljahr** (Einstellungen → Noten): 1 oder 2, Standard 2. Mit 1 gibt es keine Semester-Auswahl mehr. (#3)
* **Notenrechner:** mehrere Fächer auf einmal importieren und auch in eine schon begonnene Rechnung. (#3)
* **Stunden pro Woche** als Schieberegler, voreingestellt auf den Stundenplan. (#2)

## Windows

* Ein Klick auf eine **Benachrichtigung öffnet die App** bzw. holt das offene Fenster nach vorne. (#6)
* **Mindestgröße** fürs Fenster. (#1)
* Ein zweiter Start öffnet kein zweites Fenster mehr.
* Herausgeber in Installer und `.exe` ist jetzt Laurin Feichter. (#5)

## Behoben

* **Absturz beim Anmelden** („FormatException: Invalid radix-10 number“). Er kam, wenn statt des Registers eine andere Seite antwortete, etwa die Anmeldeseite eines WLANs. Jetzt heißt es „Das Register war nicht erreichbar“, und die App läuft offline weiter.

## Installation

* **Windows**: `digitales-register-8.6.0-setup.exe`. SmartScreen warnt beim ersten Start: *Weitere Informationen → Trotzdem ausführen*. Ohne Installation: `...-windows-x64.zip` auspacken.
* **Android**: `digitales-register-8.6.0.apk`. Die App kann das Update selbst einspielen; Android fragt dabei einmal, ob Installationen aus dieser App erlaubt sind.

Eigenständiger Fork auf Basis von [miDeb/digitales_register](https://github.com/miDeb/digitales_register), GNU GPL v3.
''';

String _plain(List<InlineSpan> spans) =>
    spans.map((s) => (s as TextSpan).toPlainText()).join();

void main() {
  group("blocks", () {
    test("headings, list items and paragraphs", () {
      final blocks = parseMarkdownBlocks(
        "## Titel\n\nErster Satz\nzweite Zeile.\n\n* Punkt eins\n  geht weiter\n- Punkt zwei\n1. Nummer",
      );
      expect(blocks.map((b) => b.kind), [
        MarkdownBlockKind.heading,
        MarkdownBlockKind.paragraph,
        MarkdownBlockKind.bullet,
        MarkdownBlockKind.bullet,
        MarkdownBlockKind.bullet,
      ]);
      expect(blocks[0].text, "Titel");
      expect(blocks[0].level, 2);
      expect(blocks[1].text, "Erster Satz zweite Zeile.");
      expect(blocks[2].text, "Punkt eins geht weiter");
      expect(blocks[4].marker, "1.");
    });

    test("an underlined line is a heading, a lone rule is nothing", () {
      final blocks = parseMarkdownBlocks(
        "Krank melden\n------------\nText\n\n---\n\nTitel\n=====",
      );
      expect(blocks.map((b) => b.kind), [
        MarkdownBlockKind.heading,
        MarkdownBlockKind.paragraph,
        MarkdownBlockKind.heading,
      ]);
      expect(blocks[0].text, "Krank melden");
      expect(blocks[0].level, 2);
      expect(blocks[2].level, 1);
    });

    test("a bold line is not a list item", () {
      final blocks = parseMarkdownBlocks("**Wichtig.** Text");
      expect(blocks.single.kind, MarkdownBlockKind.paragraph);
    });
  });

  group("inline", () {
    test("removes the markers and keeps the text", () {
      final spans = markdownInline(
        "**fett** und *kursiv* und `code` und [Link](https://x.y) und _so_",
      );
      expect(_plain(spans), "fett und kursiv und code und Link und so");
      final bold = spans.first as TextSpan;
      expect(bold.style!.fontWeight, FontWeight.bold);
    });

    test("leaves underscores inside words alone", () {
      expect(
        _plain(markdownInline("digitales_register_main")),
        "digitales_register_main",
      );
    });
  });

  testWidgets("the 8.6.0 notes show without Markdown markers", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SimpleMarkdown(_releaseNotes)),
        ),
      ),
    );
    final shown = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((t) => t.text.toPlainText())
        .join("\n");
    expect(shown, contains("Begründung"));
    expect(shown, contains("Krank melden / vorentschuldigen"));
    expect(shown, isNot(contains("**")));
    expect(shown, isNot(contains("## ")));
    expect(shown, isNot(contains("](")));
    expect(tester.takeException(), isNull);
  });

  // The dialog sizes its content intrinsically; long notes must scroll
  // inside it without a layout error and leave the buttons reachable.
  testWidgets("the update dialog shows the notes formatted", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateDialog(
              context,
              UpdateInfo(
                version: AppVersion.tryParse("8.6.0")!,
                notes: _releaseNotes,
                build: null,
              ),
            ),
            child: const Text("open"),
          ),
        ),
      ),
    );
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SimpleMarkdown), findsOneWidget);
    expect(find.text("Später"), findsOneWidget);
    expect(tester.getBottomLeft(find.text("Später")).dy,
        lessThanOrEqualTo(tester.view.physicalSize.height));
  });
}
