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

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/app_state.dart';
import 'package:dr/demo.dart';
import 'package:dr/main.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:mutex/mutex.dart';

/*
// Debug all requests
// IMPORTANT Don't include in release, contains sensitive info
class DebugInterceptor extends Interceptor {
  @override
  Future onRequest(RequestOptions options) async {
    log("Request, uri: ${options.uri},\ndata: ${options.data},\nheaders: ${options.headers}");
    return super.onRequest(options);
  }

  @override
  Future onResponse(Response response) async {
    log("Response, uri: ${response.request.uri},\nheaders: ${response.headers}");
    if (response.data.toString().length <= 100) {
      log(response.data.toString());
    } else {
      log(response.data.toString().substring(0, 100));
    }
    return response;
  }

  @override
  Future onError(DioError err) async => err;
}
*/
typedef AddNetworkProtocolItem = void Function(NetworkProtocolItem item);

class UnexpectedLogoutException implements Exception {}

/// The register's start page was not what came back — see
/// [Wrapper.parseConfig].
class ConfigUnavailableException implements Exception {
  const ConfigUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => "ConfigUnavailableException: $reason";
}

class Wrapper {
  final cookieJar = DefaultCookieJar();
  final Dio dio = Dio();
  String get loginAddress => "${baseAddress}api/auth/login";
  String get baseAddress => "$url/v2/";
  String? user, pass, _url;
  bool demoMode = false;

  Wrapper() {
    dio.interceptors.add(CookieManager(cookieJar));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..userAgent =
            "Digitales-Register-App $appVersion; https://github.com/miDeb/digitales_register",
    );
    //dio.interceptors.add(DebugInterceptor());
  }

  String? get url => _url;
  set url(String? value) {
    if (value != _url) {
      // we should already be logged out, but why not double check
      logout(hard: true);
    }
    _url = value;
  }

  Future<bool> get loggedIn => _loggedIn;
  // This future will be not completed if a login is in progress
  Future<bool> _loggedIn = Future.value(false);
  VoidCallback? onLogout, onConfigLoaded, onRelogin;
  AddNetworkProtocolItem? onAddProtocolItem;
  late bool safeMode;

  bool noInternet = false;
  Future<bool> refreshNoInternet() async {
    final address = url != null ? baseAddress : "https://digitalesregister.it";
    return noInternet = await cannotConnectTo(address);
  }

  String? error;

  DateTime lastInteraction = DateTime.now();
  DateTime? _serverLogoutTime;
  late Config config;
  Future<dynamic> login(
    String? user,
    String? pass,
    String? tfaCode,
    String? url, {
    VoidCallback? logout,
    VoidCallback? configLoaded,
    VoidCallback? relogin,
    AddNetworkProtocolItem? addProtocolItem,
  }) async {
    if (isDemoUser(url: url, username: user)) {
      demoMode = true;
      _loggedIn = Future.value(true);
      this.user = user;
      this.pass = pass;
      config = Config(
        (b) => b
          ..autoLogoutSeconds = 300
          ..currentSemesterMaybe = 1
          ..fullName = "Demo User"
          ..imgSource =
              "https://vinzentinum.digitalesregister.it/v2/theme/icons/profile_empty.png"
          ..isStudentOrParent = true
          ..userId = 0,
      );
      configLoaded?.call();
      return;
    } else {
      demoMode = false;
    }

    noInternet = false;
    if (logout != null) {
      onLogout = logout;
    } else {
      assert(onLogout != null);
    }
    if (configLoaded != null) {
      onConfigLoaded = configLoaded;
    } else {
      assert(onConfigLoaded != null);
    }
    if (relogin != null) {
      onRelogin = relogin;
    } else {
      assert(onRelogin != null);
    }
    if (addProtocolItem != null) {
      onAddProtocolItem = addProtocolItem;
    } else {
      assert(onAddProtocolItem != null);
    }
    this.url = url;
    final loggedInCompleter = Completer<bool>();
    _loggedIn = loggedInCompleter.future;
    Map response;
    _clearCookies();
    try {
      response = getMap(
        (await dio.post<dynamic>(
          loginAddress,
          data: {
            "username": user,
            "password": pass,
            if (tfaCode != null) "two_factor": tfaCode,
          },
        ))
            .data,
      )!;
    } catch (e) {
      loggedInCompleter.complete(false);
      log("Error while logging in (login failed)", error: e);
      if (e is TimeoutException || await refreshNoInternet()) {
        noInternet = true;
      }
      error = "Unknown Error:\n$e";
      return null;
    }
    if (getBool(response["loggedIn"]) ?? false) {
      log("login succeeded");
      this.user = user;
      this.pass = pass;
      error = null;

      // The login can succeed and the next page still not be the register: a
      // wifi that redirects to its own sign-in page, a maintenance page, or a
      // session cookie that did not stick. That used to surface as
      // "FormatException: Invalid radix-10 number ... ml>" on the error screen
      // — the parser found no user id and read from the page's 13th character
      // on. Now it is treated as what it is: no usable connection.
      try {
        config = await _loadConfigWithRetry();
      } catch (e) {
        log("login succeeded but the register page could not be read",
            error: e);
        loggedInCompleter.complete(false);
        noInternet = true;
        error = "Das Register war nicht erreichbar. Bist du mit einem WLAN "
            "verbunden, das erst eine Anmeldung im Browser verlangt?";
        return null;
      }

      lastInteraction = DateTime.now();
      loggedInCompleter.complete(true);
      _serverLogoutTime =
          DateTime.now().add(Duration(seconds: config.autoLogoutSeconds));
      _updateLogout();
      onConfigLoaded!();
    } else {
      log("login did not succeed");
      loggedInCompleter.complete(false);
      error = "[${response["error"]}] ${response["message"]}";
      switch (getString(response["error"])) {
        case "two_factor_needed":
          final tfaCode = await _request2FA();
          if (tfaCode != null) {
            return login(user, pass, tfaCode, url);
          }
          return;
        case "two_factor_wrong":
          final tfaCode = await _request2FA(wasWrong: true);
          if (tfaCode != null) {
            return login(user, pass, tfaCode, url);
          }
          return;
      }
    }
    return response;
  }

  Future<String?> _request2FA({bool wasWrong = false}) {
    return showDialog(
      context: navigatorKey!.currentContext!,
      builder: (context) {
        final textInputController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => InfoDialog(
            title: Text(
                wasWrong ? "Ungültiger Code" : "Zweiter Faktor wird benötigt"),
            content: TextField(
              controller: textInputController,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Abbrechen"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  textInputController.value.text,
                ),
                child: const Text("Bestätigen"),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<dynamic> changePass(
      String url, String user, String oldPass, String newPass) async {
    this.url = url;
    Map response;
    _clearCookies();
    try {
      response = getMap((await dio.post<dynamic>(
        "${baseAddress}api/auth/setNewPassword",
        data: {
          "username": user,
          "oldPassword": oldPass,
          "newPassword": newPass,
        },
      ))
          .data)!;
    } catch (e) {
      _loggedIn = Future.value(false);
      log("Failed to change pass", error: e);
      error = "Unknown Error:\n$e";
      return null;
    }
    if (response["error"] != null) {
      error = "[${response["error"]}] ${response["message"]}";
    } else {
      _loggedIn = Future.value(false);
      this.user = user;
      pass = newPass;
      error = null;
    }
    return response;
  }

  /// Fetches and parses the register's start page, once more after a short
  /// pause if the first answer was not the register.
  ///
  /// The retry covers a session cookie that needs a moment after the login; a
  /// captive portal or maintenance page fails twice and is reported.
  Future<Config> _loadConfigWithRetry() async {
    try {
      return await _loadConfig();
    } on ConfigUnavailableException catch (e) {
      log("register page not recognised, retrying once", error: e);
      await Future<void>.delayed(const Duration(seconds: 1));
      return _loadConfig();
    }
  }

  Future<Config> _loadConfig() async {
    final source = (await dio.get<String>(baseAddress)).data;
    if (source == null) {
      throw const ConfigUnavailableException("empty response");
    }
    return parseConfig(source);
  }

  /// Reads what the app needs from the register's start page.
  ///
  /// Throws [ConfigUnavailableException] when the page is not the register —
  /// the user id is the one value without which nothing works, so its absence
  /// is the test. Everything else falls back to a harmless default rather than
  /// failing the whole login over a missing profile picture.
  static Config parseConfig(String source) {
    final id = _readUserId(source);
    if (id == null) {
      throw ConfigUnavailableException(
        "no user id on the page (starts with: "
        "${source.substring(0, source.length < 60 ? source.length : 60)})",
      );
    }
    final fullName = _readFullName(source);
    final imgSource = _readImgSource(source);
    final autoLogout = _readAutoLogoutSeconds(source);
    final currentSemesterMaybe = _readCurrentSemester(source);
    final isStudentOrParent = _readIsStudentOrParent(source);
    return Config(
      (b) => b
        ..userId = id
        ..autoLogoutSeconds = autoLogout
        ..fullName = fullName
        ..imgSource = imgSource
        ..currentSemesterMaybe = currentSemesterMaybe
        ..isStudentOrParent = isStudentOrParent,
    );
  }

  /// The text between [marker] and the next [terminator], or null when the
  /// marker is not on the page at all.
  ///
  /// `indexOf` returns -1 for a missing marker, and the old code added the
  /// marker's length to that — reading from a fixed offset into whatever page
  /// it got. This is the one place that check now lives.
  static String? _valueAfter(String source, String marker, String terminator) {
    final start = source.indexOf(marker);
    if (start < 0) return null;
    final from = start + marker.length;
    final end = source.indexOf(terminator, from);
    if (end < 0) return null;
    return source.substring(from, end).trim();
  }

  static bool _readIsStudentOrParent(String source) {
    return !source.contains("var isStudentOrParent=0;");
  }

  static int? _readCurrentSemester(String source) {
    if (source.contains("semesterWechsel=1")) return 2;
    if (source.contains("semesterWechsel=2")) {
      return 1;
    } else {
      return null;
    }
  }

  /// The register logs a session out after this long without activity; used
  /// when the page does not say.
  static const _defaultAutoLogoutSeconds = 300;

  static int _readAutoLogoutSeconds(String source) {
    final raw = _valueAfter(source, "auto_logout_seconds: ", ",");
    return int.tryParse(raw ?? "") ?? _defaultAutoLogoutSeconds;
  }

  static int? _readUserId(String source) {
    final raw = _valueAfter(source, "currentUserId=", ";");
    return raw == null ? null : int.tryParse(raw);
  }

  static String? _readAfterImgId(String source) {
    const marker = "navigationProfilePicture";
    final start = source.indexOf(marker);
    if (start < 0) return null;
    return source.substring(start + marker.length).trim();
  }

  static String _readFullName(String source) {
    final afterImgId = _readAfterImgId(source);
    if (afterImgId == null) return "";
    final open = afterImgId.indexOf(">");
    final close = afterImgId.indexOf("<", open + 1);
    if (open < 0 || close < 0) return "";
    return afterImgId.substring(open + 1, close).trim();
  }

  static String _readImgSource(String source) {
    final afterImgId = _readAfterImgId(source);
    if (afterImgId == null) return "";
    return _valueAfter(afterImgId, 'src="', '"') ?? "";
  }

  final _loginMutex = Mutex();
  DateTime? _lastUnexpectedLogout;

  Future<bool> ensureLoggedIn({
    bool isRetryAfterUnexpectedLogout = false,
  }) async {
    await _loginMutex.acquire();
    try {
      // If we somehow did not yet notice that we were logged out set the flag now
      if (_serverLogoutTime != null &&
          DateTime.now().isAfter(_serverLogoutTime!)) {
        _loggedIn = Future.value(false);
      }
      if (isRetryAfterUnexpectedLogout) {
        // If we noticed an unexpected logout, we set the loggedIn flag here and try logging in again.
        // Since this has the potential of ending up in an infinite loop we only attempt a login following an unexpected logout
        // at most once every minute.
        if (_lastUnexpectedLogout
                ?.add(const Duration(minutes: 1))
                .isAfter(DateTime.now()) ??
            false) {
          log("unexpected logout: not trying to relogin, last relogin attempt was less than a minute ago.");
          log("  retrying just the request (we might have logged in in the meantime, as requests are running in parallel).");
        } else {
          log("unexpected logout: trying to relogin and retrying the request after that.");
          _loggedIn = Future.value(false);
          _lastUnexpectedLogout = DateTime.now();
        }
      }

      if (!await _loggedIn) {
        if (user != null && pass != null) {
          await login(user, pass, null, url);
          if (!await _loggedIn) {
            if (noInternet) {
              await actions.noInternet(true);
            } else {
              logout(hard: true, logoutForcedByServer: true);
            }
            return false;
          } else {
            onRelogin!();
          }
        } else {
          if (noInternet) {
            await actions.noInternet(true);
          }
          return false;
        }
      }
    } finally {
      _loginMutex.release();
    }
    return true;
  }

  Future<dynamic> send(
    String url, {
    Map<String, Object?> args = const <String, Object?>{},
    String method = "POST",
    bool isRetryAfterUnexpectedLogout = false,
  }) async {
    if (demoMode) {
      return getDemoResponse(url, args);
    }
    assert(!url.startsWith("/"));

    if (!await ensureLoggedIn(
      isRetryAfterUnexpectedLogout: isRetryAfterUnexpectedLogout,
    )) {
      log("returning null for request to $url, user is not logged in");
      return null;
    }

    dynamic responseData;
    try {
      final response = await (method == "POST"
          ? dio.post<dynamic>(
              baseAddress + url,
              data: args,
            )
          : method == "GET"
              ? dio.get<dynamic>(
                  baseAddress + url,
                )
              : throw Exception(
                  "invalid method: $method; expected POST or GET"));
      responseData = response.data;
    } on Exception catch (e) {
      if (e is DioException &&
          isSessionTakenOver(e.response?.statusCode, e.response?.data)) {
        // The register keeps one session per user: logging in anywhere else
        // (another device, the website) ends this one, and every request
        // then gets a 401 (#18). Log in again once and repeat the request, so
        // that saving a note or an absence still goes through. A second 401
        // means the other login keeps winning; then give up instead of
        // taking the session back and forth.
        onAddProtocolItem!(NetworkProtocolItem((b) => b
          ..address = baseAddress + url
          ..response = stringifyMaybeJson(e.response?.data)
          ..parameters = stringifyMaybeJson(args)));
        if (isRetryAfterUnexpectedLogout) {
          log("still logged out after logging in again, giving up on $url");
          error = "Die Sitzung wurde von einer anderen Anmeldung beendet.";
          return null;
        }
        log("session ended by another login, logging in again once");
        return send(
          url,
          args: args,
          method: method,
          isRetryAfterUnexpectedLogout: true,
        );
      }
      await _handleError(e);
      onAddProtocolItem!(NetworkProtocolItem((b) => b
        ..address = baseAddress + url
        ..response = stringifyMaybeJson(responseData)
        ..parameters = stringifyMaybeJson(args)));
      return null;
    }
    onAddProtocolItem!(NetworkProtocolItem((b) => b
      ..address = baseAddress + url
      ..response = stringifyMaybeJson(responseData)
      ..parameters = stringifyMaybeJson(args)));

    // returned if we were logged out (there should be whitespace at both ends, but the editor is removing it):
    //	<script type="text/javascript">
    //window.location = "https://vinzentinum.digitalesregister.it/v2/login";
    //</script>

    if (responseData is String &&
        RegExp(r'^[\s\n]*<script type="text/javascript">\n?\s*window\.location = "https://.+\.digitalesregister.it/v2/login";\n?\s*</script>[\s\n]*$')
            .hasMatch(responseData)) {
      // This is a very frequently reported bug, but I don't have an idea as to why this is happening.
      // Possible causes might be that the user's time is off, or the user might be trying to log in from a different device at the same time.

      // If this is already a retry, don't retry again. We really don't know anymore what's going on.
      if (isRetryAfterUnexpectedLogout) {
        log("retrying the request was unsuccessful, we seem to be still logged out.");
        throw UnexpectedLogoutException();
      }

      // Retry the request.
      return send(
        url,
        args: args,
        method: method,
        isRetryAfterUnexpectedLogout: true,
      );
    }
    return responseData;
  }

  /// What the register answers once another login has ended this session:
  /// 401 with `{"forceLogout": true, "noSession": true}`.
  static bool isSessionTakenOver(int? statusCode, dynamic body) {
    if (statusCode != 401) return false;
    final map = body is String ? _tryDecode(body) : body;
    return map is Map &&
        (map["forceLogout"] == true || map["noSession"] == true);
  }

  static dynamic _tryDecode(String body) {
    try {
      return json.decode(body);
    } on FormatException {
      return null;
    }
  }

  Future<void> _handleError(Exception e) async {
    log("Error while sending request", error: e);
    if (e is TimeoutException || await refreshNoInternet()) {
      noInternet = true;
      _loggedIn = Future.value(false);
      await actions.noInternet(true);
      error = "Keine Internetverbindung";
    } else {
      error = e.toString();
    }
  }

  Future<void> _updateLogout() async {
    if (!await _loggedIn) return;
    if (demoMode) return;
    if (_serverLogoutTime != null &&
        DateTime.now()
            .add(const Duration(seconds: 25))
            .isAfter(_serverLogoutTime!)) {
      //autologout happens soon!
      final result = getMap(
        await send(
          "api/auth/extendSession",
          args: <String, Object?>{
            "lastAction": lastInteraction.millisecondsSinceEpoch ~/ 1000,
          },
        ),
      );
      if (result == null) {
        logout(hard: safeMode, logoutForcedByServer: true);
        return;
      }
      if (result["forceLogout"] == true) {
        logout(hard: safeMode, logoutForcedByServer: true);
        return;
      } else {
        _serverLogoutTime = DateTime.fromMillisecondsSinceEpoch(
            (result["newExpiration"] as int) * 1000);
      }
    }
    Future.delayed(const Duration(seconds: 5), _updateLogout);
  }

  void interaction() {
    lastInteraction = DateTime.now();
  }

  void logout({required bool hard, bool logoutForcedByServer = false}) {
    if (!logoutForcedByServer && _url != null) {
      dio.get<dynamic>("${baseAddress}logout");
    }
    if (hard) {
      if (logoutForcedByServer) {
        onLogout!();
      }
      _url = user = pass = null;
    }
    _loggedIn = Future.value(false);
    _clearCookies();
  }

  void _clearCookies() {
    cookieJar.deleteAll();
  }
}
