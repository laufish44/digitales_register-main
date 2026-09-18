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

import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/absences.dart';
import 'package:dr/reducer/settings.dart';
import 'package:dr/theme.dart';
import 'package:dr/update/update_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message({
  required int toUserId,
  UtcDateTime? timeRead,
  bool responseRequired = false,
  String? response,
  bool signatureRequired = false,
  String? responseSignature,
  bool needsParentSignature = false,
}) =>
    Message(
      (b) => b
        ..id = 1
        ..subject = "Betreff"
        ..text = '{"ops":[{"insert":"Hallo\\n"}]}'
        ..timeSent = UtcDateTime(2026, 9, 1)
        ..timeRead = timeRead
        ..recipientString = "Klasse"
        ..fromName = "Lehrperson"
        ..toUserId = toUserId
        ..responseRequired = responseRequired
        ..response = response
        ..signatureRequired = signatureRequired
        ..responseSignature = responseSignature
        ..needsParentSignature = needsParentSignature,
    );

void main() {
  group("Message.isNew", () {
    test("a plain incoming message is read once it has a timeRead", () {
      expect(_message(toUserId: 5).isNew, isTrue);
      expect(
        _message(toUserId: 5, timeRead: UtcDateTime(2026, 9, 2)).isNew,
        isFalse,
      );
    });

    test("messages the user sent are never flagged", () {
      // toUserId 0 means outgoing; these used to show up as "neu" forever
      // because they have no timeRead.
      expect(_message(toUserId: 0).isNew, isFalse);
    });

    test("stays flagged while an expected answer is missing", () {
      final message = _message(
        toUserId: 5,
        timeRead: UtcDateTime(2026, 9, 2),
        responseRequired: true,
      );
      expect(message.isNew, isTrue, reason: "the server also keeps it unread");
      expect(message.needsAction, isTrue);
    });

    test("is read once the answer is there", () {
      expect(
        _message(
          toUserId: 5,
          timeRead: UtcDateTime(2026, 9, 2),
          responseRequired: true,
          response: "Einverstanden",
        ).isNew,
        isFalse,
      );
    });

    test("stays flagged while a signature is missing", () {
      expect(
        _message(
          toUserId: 5,
          timeRead: UtcDateTime(2026, 9, 2),
          signatureRequired: true,
        ).isNew,
        isTrue,
      );
    });

    test("a parent signature takes the student out of the loop", () {
      expect(
        _message(
          toUserId: 5,
          timeRead: UtcDateTime(2026, 9, 2),
          responseRequired: true,
          signatureRequired: true,
          needsParentSignature: true,
        ).isNew,
        isFalse,
      );
    });

    test("needsAction only applies to messages that were opened", () {
      expect(
        _message(toUserId: 5, responseRequired: true).needsAction,
        isFalse,
        reason: "an unopened message is simply new",
      );
    });
  });

  group("looksLikeLoginPage", () {
    test("recognises the login page the server sends for unknown routes", () {
      const html = '''
        <div ng-app="loginApp">
          <h2>Anmelden mit Username / Passwort</h2>
          <a>Passwort vergessen</a>
          <span>{{error_spid}}</span>
        </div>''';
      expect(looksLikeLoginPage(html), isTrue);
    });

    test("does not mistake a certificate for it", () {
      const html = "<h1>Zeugnis</h1><p>Passwort vergessen? Nicht hier.</p>";
      expect(looksLikeLoginPage(html), isFalse);
    });
  });

  group("normalizeBackendUrl", () {
    test("adds https and keeps the port", () {
      expect(
        normalizeBackendUrl("testserver.test.com:8070"),
        "https://testserver.test.com:8070",
      );
    });

    test("leaves an explicit scheme alone", () {
      expect(normalizeBackendUrl("http://10.0.0.5:8080"), "http://10.0.0.5:8080");
    });

    test("strips trailing slashes and whitespace", () {
      expect(normalizeBackendUrl("  example.org/  "), "https://example.org");
    });

    test("keeps an empty value empty", () {
      expect(normalizeBackendUrl("   "), "");
    });
  });

  group("AppVersion", () {
    test("compares numerically, not as text", () {
      final a = AppVersion.tryParse("8.2.9")!;
      final b = AppVersion.tryParse("8.2.15")!;
      expect(b.isNewerThan(a), isTrue);
      expect(a.isNewerThan(b), isFalse);
    });

    test("treats missing parts as zero", () {
      expect(
        AppVersion.tryParse("9")!.isNewerThan(AppVersion.tryParse("8.9.9")!),
        isTrue,
      );
      expect(
        AppVersion.tryParse("8.2")!.isNewerThan(AppVersion.tryParse("8.2.0")!),
        isFalse,
      );
    });

    test("ignores a build suffix", () {
      expect(AppVersion.tryParse("8.2.15+50")!.raw, "8.2.15");
    });

    test("rejects nonsense", () {
      expect(AppVersion.tryParse("nightly"), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });
  });

  group("theme presets", () {
    test("the default is the original look", () {
      final preset = themePresetById(defaultThemePresetId);
      expect(preset.id, defaultThemePresetId);
      expect(preset.useMaterial3, isFalse);
    });

    test("the original keeps the greys the shipped app had", () {
      // Material 3 paints scaffold and cards the same near-black, which is
      // exactly what this preset exists to avoid.
      final dark = themePresetById("original").build(Brightness.dark, null);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF303030));
      expect(dark.cardColor, const Color(0xFF424242));
      expect(dark.scaffoldBackgroundColor, isNot(dark.cardColor));

      final light = themePresetById("original").build(Brightness.light, null);
      expect(light.scaffoldBackgroundColor, const Color(0xFFFAFAFA));
      expect(light.cardColor, Colors.white);
    });

    test("every preset but Modern keeps the surfaces apart", () {
      for (final preset in appThemePresets.where((p) => !p.useMaterial3)) {
        final dark = preset.build(Brightness.dark, null);
        expect(
          dark.scaffoldBackgroundColor,
          isNot(dark.cardColor),
          reason: "${preset.id} would look like one flat slab",
        );
      }
    });

    test("an unknown id falls back instead of throwing", () {
      expect(themePresetById("does-not-exist").id, appThemePresets.first.id);
      expect(themePresetById(null).id, appThemePresets.first.id);
    });

    test("every preset builds a theme in both brightnesses", () {
      for (final preset in appThemePresets) {
        for (final brightness in Brightness.values) {
          expect(preset.build(brightness, null), isA<ThemeData>());
        }
      }
    });

    test("midnight really is black in the dark", () {
      final dark = themePresetById("midnight").build(Brightness.dark, null);
      expect(dark.scaffoldBackgroundColor, Colors.black);
      // ...but not in light mode.
      final light = themePresetById("midnight").build(Brightness.light, null);
      expect(light.scaffoldBackgroundColor, isNot(Colors.black));
    });

    test("preset ids are unique", () {
      final ids = appThemePresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group("self declarations", () {
    test("are read from the absences response", () {
      final state = parseAbsencesResponse(<String, dynamic>{
        "statistics": <String, dynamic>{},
        "absences": <dynamic>[],
        "futureAbsences": <dynamic>[],
        "canEdit": true,
        "isAbsencesSelfDeclarationActive": true,
        "isAbsencesSelfDeclarationMandatory": false,
        "selfDeclarationsActiveList": <dynamic>[
          <String, dynamic>{
            "id": 3,
            "title": "Krankheit",
            "text": "Ich war krank.",
            "inputmandatory": true,
            "inputexplain": "Bitte Symptome angeben",
          },
        ],
      });

      expect(state.selfDeclarationActive, isTrue);
      expect(state.selfDeclarationMandatory, isFalse);
      expect(state.canEdit, isTrue);
      expect(state.selfDeclarations.length, 1);
      final declaration = state.selfDeclarations.single;
      expect(declaration.id, 3);
      expect(declaration.title, "Krankheit");
      expect(declaration.inputMandatory, isTrue);
      expect(declaration.inputExplain, "Bitte Symptome angeben");
    });

    test("fall back to the full list on older servers", () {
      final state = parseAbsencesResponse(<String, dynamic>{
        "statistics": <String, dynamic>{},
        "absences": <dynamic>[],
        "futureAbsences": <dynamic>[],
        "selfDeclarationsList": <dynamic>[
          <String, dynamic>{"id": 1, "title": "Krank"},
        ],
      });
      expect(state.selfDeclarations.single.title, "Krank");
      // Nothing said otherwise, so editing stays allowed.
      expect(state.canEdit, isTrue);
      expect(state.selfDeclarationActive, isFalse);
    });
  });
}
