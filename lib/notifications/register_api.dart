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

/// A minimal client for the Digitales Register API.
///
/// [Wrapper] is the client the app itself uses, but it is tied to the redux
/// store: it dispatches actions, pushes dialogs for two factor authentication
/// and writes to the network protocol. None of that works in the headless
/// Windows background service, which only ever needs to log in and read the
/// list of unread notifications — so it uses this instead.
library;

import 'dart:developer';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/notifications/notification_watcher.dart';
import 'package:dr/notifications/summaries.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

class RegisterApi {
  RegisterApi({required this.url}) {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// The server, e.g. `https://wfo-bruneck.digitalesregister.it`.
  final String url;

  final _dio = Dio();
  final _cookieJar = DefaultCookieJar();

  String get _baseAddress => "$url/v2/";

  var _loggedIn = false;
  bool get loggedIn => _loggedIn;

  /// Logs in with a stored username and password.
  ///
  /// Accounts that require a second factor cannot be used here, because there
  /// is nobody to ask for the code; [login] simply returns false for those.
  Future<bool> login(String user, String pass) async {
    try {
      final response = getMap(
        (await _dio.post<dynamic>(
          "${_baseAddress}api/auth/login",
          data: {"username": user, "password": pass},
        ))
            .data,
      );
      _loggedIn = getBool(response?["loggedIn"]) ?? false;
      if (!_loggedIn) {
        log("background login failed: ${response?["error"]}");
      }
      return _loggedIn;
    } catch (e) {
      log("background login threw", error: e);
      _loggedIn = false;
      return false;
    }
  }

  /// Returns the unread notifications, or null if the request failed.
  Future<List<dynamic>?> unreadNotifications() async {
    if (!_loggedIn) return null;
    try {
      final response = await _dio.post<dynamic>(
        "${_baseAddress}api/notification/unread",
      );
      final data = response.data;
      if (data is List) return data;
      // Being redirected to the login page means the session expired.
      _loggedIn = false;
      log("unexpected response for unread notifications: "
          "${data.runtimeType}");
      return null;
    } catch (e) {
      log("failed to fetch unread notifications", error: e);
      return null;
    }
  }

  /// Any other request, decoded; null if it failed or the session is gone.
  Future<dynamic> post(String path, [Map<String, dynamic>? args]) async {
    if (!_loggedIn) return null;
    try {
      final data =
          (await _dio.post<dynamic>("$_baseAddress$path", data: args)).data;
      // The login page instead of data: the session expired.
      if (data is String && data.contains("/v2/login")) {
        _loggedIn = false;
        return null;
      }
      return data;
    } catch (e) {
      log("background request $path failed", error: e);
      return null;
    }
  }

  Future<Map<dynamic, dynamic>?> allSubjects() async {
    final data = await post("api/student/all_subjects");
    return data is Map ? data : null;
  }

  Future<List<dynamic>?> futureDashboard() async {
    final data =
        await post("api/student/dashboard/dashboard", {"viewFuture": true});
    return data is List ? data : null;
  }

  Future<Map<String, dynamic>?> calendarWeek(UtcDateTime monday) async {
    final data = await post("api/calendar/student", {
      "startDate": "${monday.year}-${monday.month.toString().padLeft(2, "0")}-"
          "${monday.day.toString().padLeft(2, "0")}",
    });
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// The evening summary and the notifications, as one background round.
  Future<void> notifyAboutNew(List<dynamic> unread) async {
    await NotificationWatcher.notifyAboutNew(unread, loadSubjects: allSubjects);
    await EveningSummary.runIfDue(
      now: DateTime.now(),
      loadDashboard: futureDashboard,
      loadCalendar: calendarWeek,
    );
  }

  void close() => _dio.close(force: true);
}
