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

/// The headless Windows background service.
///
/// This is the same executable as the app, started with `--background`. The
/// runner keeps its window hidden (see `windows/runner/main.cpp`), so all the
/// user sees is the occasional notification. Running the same binary means the
/// service shares the stored credentials, the settings and the "already seen"
/// bookkeeping with the app, and needs no separate installation.
library;

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dr/background/credentials.dart';
import 'package:dr/notifications/notification_service.dart';
import 'package:dr/notifications/notification_store.dart';
import 'package:dr/notifications/notification_watcher.dart';
import 'package:dr/notifications/register_api.dart';
import 'package:flutter/widgets.dart';

/// Loopback port the running app binds so the service can tell it is there.
///
/// While the app itself is open it polls on its own, so the service stays quiet
/// instead of both of them announcing the same entry.
const appPresencePort = 49731;

/// Loopback port the service binds, so a second copy of it exits immediately.
const servicePresencePort = 49732;

/// How long to wait before retrying after a failed login or a lost connection.
const _backoff = Duration(minutes: 5);

Future<void> runWindowsBackgroundService() async {
  WidgetsFlutterBinding.ensureInitialized();

  final lock = await _bind(servicePresencePort);
  if (lock == null) {
    log("another background service is already running, exiting");
    exit(0);
  }

  log("background service started");
  await LocalNotificationService.init();

  RegisterApi? api;
  String? apiUrl;

  while (true) {
    var delay = Duration(seconds: await NotificationStore.intervalSeconds);
    try {
      if (!await NotificationStore.backgroundServiceEnabled ||
          !await NotificationStore.enabled) {
        log("background service disabled in the settings, exiting");
        await lock.close();
        exit(0);
      }

      if (await _isAppRunning()) {
        // The app is open and polls by itself.
        await Future<void>.delayed(delay);
        continue;
      }

      final credentials = await readStoredCredentials();
      if (credentials == null) {
        log("no stored credentials, waiting");
        await Future<void>.delayed(_backoff);
        continue;
      }

      if (api == null || apiUrl != credentials.url || !api.loggedIn) {
        api?.close();
        apiUrl = credentials.url;
        api = RegisterApi(url: credentials.url);
        if (!await api.login(credentials.user, credentials.pass)) {
          api.close();
          api = null;
          delay = _backoff;
          await Future<void>.delayed(delay);
          continue;
        }
      }

      final unread = await api.unreadNotifications();
      if (unread == null) {
        // Session expired or the server was unreachable; log in again next
        // time around.
        api.close();
        api = null;
      } else {
        await NotificationWatcher.notifyAboutNew(unread);
      }
    } catch (e, trace) {
      log("background service iteration failed", error: e, stackTrace: trace);
    }
    await Future<void>.delayed(delay);
  }
}

Future<ServerSocket?> _bind(int port) async {
  try {
    return await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  } catch (_) {
    return null;
  }
}

Future<bool> _isAppRunning() async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      appPresencePort,
      timeout: const Duration(milliseconds: 300),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Called by the app (not the service) to advertise that it is running.
Future<ServerSocket?> announceAppIsRunning() => _bind(appPresencePort);
