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

part of 'middleware.dart';

final _notificationsMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(NotificationsActionsNames.load, _loadNotifications)
      ..add(NotificationsActionsNames.loaded, _postNewNotifications)
      ..add(NotificationsActionsNames.delete, _deleteNotification)
      ..add(NotificationsActionsNames.deleteAll, _deleteAllNotifications)
      ..add(SettingsActionsNames.setNotificationsEnabled,
          _applyNotificationSettings)
      ..add(SettingsActionsNames.setNotificationInterval,
          _applyNotificationSettings)
      ..add(SettingsActionsNames.setBackgroundServiceEnabled,
          _applyBackgroundServiceSetting);

Future<void> _loadNotifications(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  if (api.state.noInternet) return;

  await next(action);
  final dynamic data = await wrapper.send("api/notification/unread");

  if (data != null) {
    await api.actions.notificationsActions.loaded(data as List);
  }
}

/// Posts a system notification for every entry the user has not seen yet.
///
/// This runs on every `loaded`, no matter whether it was triggered by the poll
/// timer, by a pull to refresh or by the app starting up, so the user is told
/// about new entries exactly once.
Future<void> _postNewNotifications(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<List> action) async {
  await next(action);
  if (!api.state.settingsState.notificationsEnabled) return;
  if (api.state.isDemo) return;
  await NotificationWatcher.notifyAboutNew(action.payload);
}

Future<void> _deleteNotification(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<Notification> action) async {
  await next(action);
  await wrapper.send(
    "api/notification/markAsRead",
    args: {"id": action.payload.id},
  );
}

Future<void> _deleteAllNotifications(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  for (final n in api.state.notificationState.notifications!
      .where((n) => n.type == "message" && n.objectId != null)) {
    await api.actions.messagesActions.markAsRead(n.objectId!);
  }
  await wrapper.send(
    "api/notification/markAsRead",
    args: {},
  );
}

/// Periodically asks the server for unread notifications while the app runs.
Timer? _notificationPollTimer;

/// Called from `_loggedIn` once the store reflects the new session.
///
/// `LoginActionsNames.loggedIn` is already handled in middleware.dart, and
/// built_redux chains handlers for the same action rather than replacing them —
/// adding a second one here would run `next(action)`, and therefore the
/// reducer, twice.
Future<void> startWatchingForNotifications(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) async {
  if (api.state.isDemo) return;

  await LocalNotificationService.init();
  await _applySettingsToSharedStore(api);
  _restartPollTimer(api);
  await _applyAndroidBackgroundCheck(api);
}

/// Hands the periodic check over to Android's AlarmManager.
///
/// The in-app timer above only runs while the app is in the foreground; this is
/// what keeps the notifications coming once it is not.
Future<void> _applyAndroidBackgroundCheck(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) async {
  if (!AndroidBackgroundCheck.isSupported) return;
  await AndroidBackgroundCheck.apply(
    enabled: api.state.settingsState.notificationsEnabled &&
        api.state.settingsState.backgroundServiceEnabled &&
        !api.state.isDemo,
  );
}

/// Called from `_logout`. See [startWatchingForNotifications] for why this is
/// not registered as a middleware handler of its own.
Future<void> stopWatchingForNotifications(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    LogoutPayload payload) async {
  _notificationPollTimer?.cancel();
  _notificationPollTimer = null;
  if (payload.hard) {
    // A different account may follow, so do not announce its backlog. There are
    // also no credentials left for the alarm to log in with, so stop it.
    await NotificationWatcher.reset();
    await AndroidBackgroundCheck.apply(enabled: false);
  }
}

Future<void> _applyNotificationSettings(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action action) async {
  await next(action);
  await _applySettingsToSharedStore(api);
  if (api.state.settingsState.notificationsEnabled) {
    await LocalNotificationService.requestPermission();
  }
  _restartPollTimer(api);
  await _applyAndroidBackgroundCheck(api);
}

Future<void> _applyBackgroundServiceSetting(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  await next(action);
  await _applySettingsToSharedStore(api);
  await _applyAndroidBackgroundCheck(api);
  if (!Platform.isWindows) return;

  final enabled = api.state.settingsState.backgroundServiceEnabled;
  final ok = await WindowsAutostart.setEnabled(enabled);
  if (!ok) {
    showSnackBar("Der Autostart konnte nicht geändert werden");
    return;
  }

  if (enabled) {
    // Start it right away instead of waiting for the next logon. It will idle
    // while the app is open, and a second copy exits immediately.
    try {
      await Process.start(
        Platform.resolvedExecutable,
        [backgroundModeFlag],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      log("failed to start the background service", error: e);
    }
  }
  // When disabled, the running service notices on its next tick and exits.
}

/// Mirrors the settings the background checks need into `shared_preferences`,
/// which they can read (the redux state is per account and encrypted, so they
/// cannot).
Future<void> _applySettingsToSharedStore(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) async {
  final settings = api.state.settingsState;
  await NotificationStore.setEnabled(settings.notificationsEnabled);
  await NotificationStore.setIntervalSeconds(
      settings.notificationIntervalSeconds);
  await NotificationStore.setBackgroundServiceEnabled(
      settings.backgroundServiceEnabled);
}

void _restartPollTimer(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) {
  _notificationPollTimer?.cancel();
  _notificationPollTimer = null;

  if (!api.state.settingsState.notificationsEnabled) return;
  if (!api.state.loginState.loggedIn) return;

  final interval =
      Duration(seconds: api.state.settingsState.notificationIntervalSeconds);
  _notificationPollTimer = Timer.periodic(interval, (_) {
    if (api.state.noInternet || !api.state.loginState.loggedIn) return;
    api.actions.notificationsActions.load();
  });
  log("notification poll timer running every ${interval.inSeconds}s");
}
