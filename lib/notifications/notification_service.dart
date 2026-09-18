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

/// Displays notifications in the notification centre of the operating system.
///
/// This is used both by the app itself (while it is running) and by the
/// Windows background service (see `lib/background/windows_background.dart`),
/// so it must not depend on the redux store.
library;

import 'dart:developer';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The Android channel new dashboard/message notifications are posted to.
const _androidChannelId = "dr_notifications";
const _androidChannelName = "Benachrichtigungen";
const _androidChannelDescription =
    "Neue Einträge, Nachrichten und Noten im Digitalen Register";

/// Identifies the app towards the Windows notification platform.
///
/// The app user model id matches `msix_config.identity_name` in `pubspec.yaml`
/// so that packaged (Microsoft Store) builds reuse the identity of the package
/// instead of registering a second one.
const _windowsAppName = "Digitales Register";
const _windowsAppUserModelId = "2097MichaelDebertol.DigitalesRegister";
const _windowsGuid = "d6e4a5c2-8f31-4b07-9c6d-2a1f5e7b3c94";

class LocalNotificationService {
  LocalNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static var _initialized = false;

  /// Whether notifications can be shown on this platform at all.
  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows ||
      Platform.isMacOS || Platform.isLinux;

  /// Prepares the platform plugin. Safe to call more than once.
  ///
  /// Returns false if notifications are unavailable, in which case the rest of
  /// the app should simply skip them rather than fail.
  static Future<bool> init({
    void Function(String? payload)? onSelected,
  }) async {
    if (_initialized) return true;
    if (!isSupported) return false;

    try {
      final settings = InitializationSettings(
        android: const AndroidInitializationSettings("@mipmap/launcher_icon"),
        iOS: const DarwinInitializationSettings(),
        macOS: const DarwinInitializationSettings(),
        linux: const LinuxInitializationSettings(defaultActionName: "Öffnen"),
        windows: const WindowsInitializationSettings(
          appName: _windowsAppName,
          appUserModelId: _windowsAppUserModelId,
          guid: _windowsGuid,
        ),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) =>
            onSelected?.call(response.payload),
      );

      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                _androidChannelId,
                _androidChannelName,
                description: _androidChannelDescription,
                importance: Importance.high,
              ),
            );
      }

      _initialized = true;
      return true;
    } catch (e, trace) {
      log("failed to initialize notifications", error: e, stackTrace: trace);
      return false;
    }
  }

  /// Asks the user for permission to post notifications.
  ///
  /// Required on Android 13+ and on iOS/macOS. Returns true if we may post.
  static Future<bool> requestPermission() async {
    if (!await init()) return false;
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            true;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (Platform.isMacOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e) {
      log("failed to request notification permission", error: e);
      return false;
    }
    // Windows and Linux do not have a runtime permission prompt.
    return true;
  }

  /// Posts a notification. Never throws.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!await init()) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e, trace) {
      log("failed to show notification", error: e, stackTrace: trace);
    }
  }
}
