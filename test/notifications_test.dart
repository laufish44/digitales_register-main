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

import 'dart:io';

import 'package:dr/file_opener.dart';
import 'package:dr/notifications/notification_store.dart';
import 'package:dr/notifications/notification_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, dynamic>> _notifications(List<int> ids) => [
      for (final id in ids)
        <String, dynamic>{
          "id": id,
          "title": "Eintrag $id",
          "subTitle": "Details zu $id",
          "type": "message",
          "objectId": id,
          "timeSent": "2026-09-14 08:00:00",
        }
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("file name handling", () {
    test("leaves a valid name untouched", () {
      // Attachments downloaded by earlier versions must still be found.
      expect(
        sanitizeFileName("msg_263_141_Programm VWL 26-27- 5. Kl..docx"),
        "msg_263_141_Programm VWL 26-27- 5. Kl..docx",
      );
    });

    test("replaces characters the platform cannot store", () {
      final sanitized = sanitizeFileName('msg_1_2_Test: a/b?c*d"e<f>g|h.pdf');
      expect(sanitized.contains("/"), isFalse);
      if (Platform.isWindows) {
        for (final c in [":", "?", "*", '"', "<", ">", "|", r"\"]) {
          expect(sanitized.contains(c), isFalse, reason: "should strip $c");
        }
      }
    });

    test("never produces an empty name", () {
      expect(sanitizeFileName("/"), isNotEmpty);
    });

    test("joins with the separator of the platform", () {
      final joined = joinPath(r"C:\Users\x\Downloads", "a.docx");
      if (Platform.isWindows) {
        // The old code produced "C:\Users\x\Downloads/a.docx".
        expect(joined, r"C:\Users\x\Downloads\a.docx");
        expect(joined.contains("/"), isFalse);
      } else {
        expect(joined.endsWith("a.docx"), isTrue);
      }
    });

    test("does not double the separator", () {
      final joined = joinPath(
        Platform.isWindows ? r"C:\Users\x\Downloads\ " .trim() : "/tmp/",
        "a.docx",
      );
      expect(joined.contains(Platform.isWindows ? r"\\" : "//"), isFalse);
    });
  });

  group("notification watcher", () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test("stays silent on the very first poll", () async {
      final posted =
          await NotificationWatcher.notifyAboutNew(_notifications([1, 2, 3]));
      expect(posted, 0, reason: "must not announce the existing backlog");
      expect(await NotificationStore.seenIds(), {"1", "2", "3"});
    });

    test("announces only entries that were not there before", () async {
      await NotificationWatcher.notifyAboutNew(_notifications([1, 2]));
      final posted =
          await NotificationWatcher.notifyAboutNew(_notifications([1, 2, 3]));
      expect(posted, 1);
    });

    test("does not announce the same entry twice", () async {
      await NotificationWatcher.notifyAboutNew(_notifications([1]));
      await NotificationWatcher.notifyAboutNew(_notifications([1, 2]));
      final posted =
          await NotificationWatcher.notifyAboutNew(_notifications([1, 2]));
      expect(posted, 0);
    });

    test("forgets entries the server no longer reports", () async {
      await NotificationWatcher.notifyAboutNew(_notifications([1, 2]));
      // 2 was read elsewhere and disappears...
      await NotificationWatcher.notifyAboutNew(_notifications([1]));
      expect(await NotificationStore.seenIds(), {"1"});
      // ...so if it ever comes back it counts as new again.
      expect(
        await NotificationWatcher.notifyAboutNew(_notifications([1, 2])),
        1,
      );
    });

    test("summarises a large batch instead of spamming", () async {
      await NotificationWatcher.notifyAboutNew(_notifications([1]));
      final posted = await NotificationWatcher.notifyAboutNew(
        _notifications([1, 2, 3, 4, 5, 6]),
      );
      expect(posted, 5);
    });

    test("ignores malformed entries", () async {
      await NotificationWatcher.notifyAboutNew(_notifications([1]));
      final posted = await NotificationWatcher.notifyAboutNew(<dynamic>[
        ..._notifications([1]),
        "not a map",
        <String, dynamic>{"title": "no id"},
      ]);
      expect(posted, 0);
    });

    test("reset makes the next poll silent again", () async {
      await NotificationWatcher.notifyAboutNew(_notifications([1]));
      await NotificationWatcher.reset();
      expect(
        await NotificationWatcher.notifyAboutNew(_notifications([1, 2])),
        2,
        reason: "reset clears the list but keeps it initialised",
      );
    });
  });

  group("notification settings store", () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test("defaults", () async {
      expect(await NotificationStore.enabled, isTrue);
      expect(await NotificationStore.intervalSeconds,
          defaultNotificationIntervalSeconds);
      expect(await NotificationStore.backgroundServiceEnabled, isFalse);
    });

    test("clamps an out of range interval", () async {
      await NotificationStore.setIntervalSeconds(1);
      expect(await NotificationStore.intervalSeconds,
          minNotificationIntervalSeconds);
      await NotificationStore.setIntervalSeconds(999999);
      expect(await NotificationStore.intervalSeconds,
          maxNotificationIntervalSeconds);
    });

    test("round trips the values the background service reads", () async {
      await NotificationStore.setEnabled(false);
      await NotificationStore.setIntervalSeconds(120);
      await NotificationStore.setBackgroundServiceEnabled(true);
      expect(await NotificationStore.enabled, isFalse);
      expect(await NotificationStore.intervalSeconds, 120);
      expect(await NotificationStore.backgroundServiceEnabled, isTrue);
    });
  });
}
