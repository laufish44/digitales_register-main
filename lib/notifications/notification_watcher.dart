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

/// Turns the server's list of unread notifications into desktop/phone
/// notifications, without ever announcing the same entry twice.
///
/// Used by the app while it is running and by the Windows background service.
library;

import 'dart:developer';

import 'package:dr/notifications/notification_service.dart';
import 'package:dr/notifications/notification_store.dart';
import 'package:dr/util.dart';

/// Beyond this many new entries a single summary is shown instead of one
/// notification per entry.
const _maxIndividualNotifications = 3;

class NotificationWatcher {
  NotificationWatcher._();

  /// Compares [rawNotifications] (the decoded `api/notification/unread`
  /// response) with what the user has already seen and posts the difference.
  ///
  /// Returns the number of notifications that were posted.
  static Future<int> notifyAboutNew(List<dynamic> rawNotifications) async {
    final entries = <_Entry>[];
    for (final raw in rawNotifications) {
      // A single unexpected entry must not stop us from telling the user about
      // the others, and must never take down the background service.
      try {
        final map = raw is Map ? raw : getMap(raw);
        if (map == null) continue;
        final id = getInt(map["id"]);
        if (id == null) continue;
        entries.add(
          _Entry(
            id: id,
            title: getString(map["title"]) ?? "Digitales Register",
            subTitle: getString(map["subTitle"]),
          ),
        );
      } catch (e) {
        log("skipping unparseable notification", error: e);
      }
    }

    final currentIds = entries.map((e) => e.id.toString()).toList();
    final seen = await NotificationStore.seenIds();

    if (seen == null) {
      // First run on this device: adopt the current state silently.
      await NotificationStore.setSeenIds(currentIds);
      log("notification watcher initialised with ${currentIds.length} entries");
      return 0;
    }

    final fresh =
        entries.where((e) => !seen.contains(e.id.toString())).toList();

    // Record before showing, so a crash while posting cannot cause the same
    // notification to be shown again on the next poll.
    await NotificationStore.setSeenIds(currentIds);

    if (fresh.isEmpty) return 0;

    if (fresh.length <= _maxIndividualNotifications) {
      for (final entry in fresh) {
        await LocalNotificationService.show(
          id: entry.id,
          title: entry.title,
          body: entry.subTitle ?? "Neu im Digitalen Register",
          payload: entry.id.toString(),
        );
      }
    } else {
      await LocalNotificationService.show(
        id: _summaryNotificationId,
        title: "${fresh.length} neue Benachrichtigungen",
        body: fresh.take(3).map((e) => e.title).join(", "),
      );
    }
    log("posted ${fresh.length} new notification(s)");
    return fresh.length;
  }

  /// Forgets everything, so the next poll adopts the server state silently.
  ///
  /// Used when the user logs out or switches accounts.
  static Future<void> reset() => NotificationStore.setSeenIds(const []);
}

/// A fixed id so repeated summaries replace each other instead of stacking up.
const _summaryNotificationId = 0x7fffffff;

class _Entry {
  _Entry({required this.id, required this.title, this.subTitle});

  final int id;
  final String title;
  final String? subTitle;
}
