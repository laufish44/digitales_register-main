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

/// The Android background check.
///
/// Where Windows keeps a process of its own alive (see `windows_background.dart`),
/// Android forbids that — an app that is not in the foreground gets no runtime.
/// The system's own AlarmManager is the way in: it wakes the app every so often,
/// runs [androidBackgroundCheck] in a short lived isolate, and puts the process
/// back to sleep.
///
/// This replaces the push backend entirely. Nothing here talks to a server of
/// ours; the check speaks to the school's register directly, exactly like the
/// app does while it is open.
library;

import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:dr/background/credentials.dart';
import 'package:dr/notifications/notification_service.dart';
import 'package:dr/notifications/notification_store.dart';
import 'package:dr/notifications/notification_watcher.dart';
import 'package:dr/notifications/register_api.dart';
import 'package:flutter/widgets.dart';

/// How often the system wakes us.
///
/// Android coalesces inexact alarms, so the real spacing drifts a little and
/// grows while the device is in doze — that is the price of not draining the
/// battery, and 15 minutes is the interval Android itself treats as the
/// sensible floor for periodic background work.
const androidCheckInterval = Duration(minutes: 15);

/// A fixed id, so rescheduling replaces the existing alarm instead of adding
/// a second one.
const _alarmId = 2410;

class AndroidBackgroundCheck {
  AndroidBackgroundCheck._();

  static bool get isSupported => Platform.isAndroid;

  static var _initialized = false;

  /// Starts or stops the periodic alarm to match [enabled].
  ///
  /// Safe to call as often as you like: scheduling the same id again simply
  /// replaces the previous alarm.
  static Future<void> apply({required bool enabled}) async {
    if (!isSupported) return;
    try {
      if (!_initialized) {
        await AndroidAlarmManager.initialize();
        _initialized = true;
      }
      if (!enabled) {
        await AndroidAlarmManager.cancel(_alarmId);
        log("android background check cancelled");
        return;
      }
      final scheduled = await AndroidAlarmManager.periodic(
        androidCheckInterval,
        _alarmId,
        androidBackgroundCheck,
        // Survives a restart of the phone; without it the user would have to
        // open the app once after every reboot.
        rescheduleOnReboot: true,
        // `exact` and `wakeup` stay at their defaults (both false) on purpose:
        // an exact alarm would need SCHEDULE_EXACT_ALARM plus a permission the
        // user has to grant by hand on Android 12+, and waking a sleeping
        // device every quarter of an hour is not worth the battery.
      );
      log("android background check scheduled: $scheduled");
    } catch (e, trace) {
      log("failed to schedule the android background check",
          error: e, stackTrace: trace);
    }
  }
}

/// Runs in a separate isolate that the alarm service starts for us.
///
/// Must be a top level function annotated with `vm:entry-point`, otherwise tree
/// shaking drops it from the release build and the alarm has nothing to call.
@pragma("vm:entry-point")
Future<void> androidBackgroundCheck() async {
  // The isolate is a fresh one: it has no plugins registered and no binding.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  RegisterApi? api;
  try {
    if (!await NotificationStore.enabled) {
      log("background check: notifications are switched off");
      return;
    }

    final credentials = await readStoredCredentials();
    if (credentials == null) {
      log("background check: no stored credentials");
      return;
    }

    await LocalNotificationService.init();

    api = RegisterApi(url: credentials.url);
    if (!await api.login(credentials.user, credentials.pass)) {
      log("background check: login failed");
      return;
    }

    final unread = await api.unreadNotifications();
    if (unread == null) {
      log("background check: could not read the notifications");
      return;
    }
    await NotificationWatcher.notifyAboutNew(unread);
  } catch (e, trace) {
    // Never let this throw: an uncaught error here takes down the alarm
    // service and Android stops waking us.
    log("background check failed", error: e, stackTrace: trace);
  } finally {
    api?.close();
  }
}

