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

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/messages_actions.dart';

import 'package:dr/actions/notifications_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

final notificationsReducerBuilder = NestedReducerBuilder<AppState,
    AppStateBuilder, NotificationState, NotificationStateBuilder>(
  (s) => s.notificationState,
  (b) => b.notificationState,
)
  ..add(NotificationsActionsNames.loaded, _loaded)
  ..add(NotificationsActionsNames.delete, _delete)
  ..add(NotificationsActionsNames.deleteAll, _deleteAll)
  ..add(MessagesActionsNames.markAsRead, _markMessageAsRead);

/// How many notifications the history keeps.
const notificationHistoryLength = 300;

void _loaded(NotificationState state, Action<List> action,
    NotificationStateBuilder builder) {
  final notifications = tryParse(action.payload, _parseNotifications);
  builder
    ..notifications = notifications
    ..lastFetched = UtcDateTime.now()
    ..history = ListBuilder(mergeNotificationHistory(
      state.history ?? BuiltList<Notification>(),
      notifications.build(),
    ));
}

/// [history] with the [incoming] notifications it does not have yet, newest
/// first and no longer than [notificationHistoryLength].
List<Notification> mergeNotificationHistory(
    Iterable<Notification> history, Iterable<Notification> incoming) {
  final byId = <int, Notification>{
    for (final n in history) n.id: n,
    for (final n in incoming) n.id: n,
  };
  final merged = byId.values.toList()
    ..sort((a, b) => b.timeSent.compareTo(a.timeSent));
  return merged.length > notificationHistoryLength
      ? merged.sublist(0, notificationHistoryLength)
      : merged;
}

ListBuilder<Notification> _parseNotifications(List data) {
  return ListBuilder(
    data.map<Notification>(
      (dynamic n) => tryParse(
        getMap(n),
        (dynamic n) => Notification(
          (b) => b
            ..id = getInt(n["id"])
            ..title = getString(n["title"])
            ..type = getString(n["type"])
            ..objectId = getInt(n["objectId"])
            ..subTitle = getString(n["subTitle"])
            ..timeSent = UtcDateTime.parse(getString(n["timeSent"])!),
        ),
      ),
    ),
  );
}

void _markMessageAsRead(NotificationState state, Action<int> action,
    NotificationStateBuilder builder) {
  builder.notifications.removeWhere((n) => n.objectId == action.payload);
}

void _delete(NotificationState state, Action<Notification> action,
    NotificationStateBuilder builder) {
  builder.notifications.remove(action.payload);
}

void _deleteAll(NotificationState state, Action<void> action,
    NotificationStateBuilder builder) {
  builder.notifications.removeWhere((n) => n.type != "message");
}
