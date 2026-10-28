// Copyright (C) 2026 Laurin Feichter
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

/// A connection log for tracking down lost connections.
///
/// Only in builds made with `--dart-define=DR_DIAGNOSTICS=true`; in every
/// other build all of this does nothing. It writes to
/// `<app data>/diagnose/verbindung-YYYY-MM-DD.log`:
///
///  * every request to the register (time, duration, status, kind of error —
///    never passwords or what came back),
///  * logins, relogins, logouts and session extensions,
///  * every switch to offline and back, with what caused it,
///  * the app going to the background and coming back,
///  * every 30 seconds an independent check: network adapters, DNS, the
///    internet in general and the register — so a lost connection can be told
///    apart from a register that hangs or an app that only thinks it is
///    offline.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

const diagnosticsEnabled = bool.fromEnvironment("DR_DIAGNOSTICS");

class Diagnostics {
  Diagnostics._();

  static Directory? _dir;
  static Timer? _probeTimer;
  static String? _lastInterfaces;

  /// Where the logs are, for the settings page.
  static Directory? get directory => _dir;

  static Future<void> start({required String version}) async {
    if (!diagnosticsEnabled) return;
    try {
      final base = await getApplicationSupportDirectory();
      _dir = Directory("${base.path}${Platform.pathSeparator}diagnose");
      await _dir!.create(recursive: true);
      log(
          "start",
          "Diagnose-Version $version, ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, "
              "Zeitzone ${DateTime.now().timeZoneName}");
      _probeTimer = Timer.periodic(const Duration(seconds: 30), (_) => probe());
      unawaited(probe());
    } catch (e) {
      developer.log("diagnostics could not start", error: e);
    }
  }

  static File _file() {
    final now = DateTime.now();
    final day = "${now.year}-${_two(now.month)}-${_two(now.day)}";
    return File("${_dir!.path}${Platform.pathSeparator}verbindung-$day.log");
  }

  static String _two(int v) => v.toString().padLeft(2, "0");

  static String _time() {
    final n = DateTime.now();
    return "${_two(n.hour)}:${_two(n.minute)}:${_two(n.second)}."
        "${n.millisecond.toString().padLeft(3, "0")}";
  }

  /// One line in the log.
  static void log(String category, String message) {
    if (!diagnosticsEnabled || _dir == null) return;
    try {
      // Written straight away: if the app is closed or crashes, the last
      // lines are the ones that matter.
      _file().writeAsStringSync("${_time()} [$category] $message\n",
          mode: FileMode.append, flush: true);
    } catch (_) {
      // A log that cannot be written must not break the app.
    }
  }

  /// A line with the caller's stack, shortened to the app's own frames.
  static void logWithStack(String category, String message) {
    if (!diagnosticsEnabled) return;
    final frames = StackTrace.current
        .toString()
        .split("\n")
        .where((l) => l.contains("package:dr/") && !l.contains("diagnostics"))
        .take(6)
        .map((l) => l.replaceAll(RegExp(r"^#\d+\s+"), "").trim())
        .join(" <- ");
    log(category, "$message | $frames");
  }

  static void stop() => _probeTimer?.cancel();

  static String describeError(Object e) {
    if (e is DioException) {
      return "DioException.${e.type.name} status=${e.response?.statusCode} "
          "inner=${e.error?.runtimeType}: ${_short(e.error?.toString() ?? e.message)}";
    }
    return "${e.runtimeType}: ${_short(e.toString())}";
  }

  static String _short(String? s) {
    if (s == null) return "";
    final one = s.replaceAll(RegExp(r"\s+"), " ");
    return one.length > 200 ? "${one.substring(0, 200)}…" : one;
  }

  /// The independent check, see the library comment.
  static Future<void> probe() async {
    if (!diagnosticsEnabled) return;
    final parts = <String>[];

    try {
      final interfaces = await NetworkInterface.list();
      final summary = interfaces
          .map((i) =>
              "${i.name}=${i.addresses.where((a) => a.type == InternetAddressType.IPv4).map((a) => a.address).join("/")}")
          .join(", ");
      if (summary != _lastInterfaces) {
        log("netz", "Adapter geändert: ${summary.isEmpty ? "keine" : summary}");
        _lastInterfaces = summary;
      }
    } catch (e) {
      parts.add("adapter=FEHLER ${describeError(e)}");
    }

    Future<String> timed(String name, Future<String> Function() run) async {
      final watch = Stopwatch()..start();
      try {
        final result = await run().timeout(const Duration(seconds: 10));
        return "$name=$result ${watch.elapsedMilliseconds}ms";
      } catch (e) {
        return "$name=FEHLER(${e is TimeoutException ? "Zeitüberschreitung" : describeError(e)}) ${watch.elapsedMilliseconds}ms";
      }
    }

    parts.add(await timed("dns", () async {
      final r =
          await InternetAddress.lookup("wfo-bruneck.digitalesregister.it");
      return r.isEmpty ? "leer" : r.first.address;
    }));
    parts.add(await timed("internet",
        () => _get("http://www.msftconnecttest.com/connecttest.txt")));
    parts.add(await timed("register",
        () => _get("https://wfo-bruneck.digitalesregister.it/v2/")));
    log("probe", parts.join("  "));
  }

  static Future<String> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      await response.drain<void>();
      return "${response.statusCode}";
    } finally {
      client.close(force: true);
    }
  }
}

/// Logs every request the app makes to the register.
class DiagnosticsInterceptor extends Interceptor {
  static const _sensitive = {
    "password",
    "oldPassword",
    "newPassword",
    "two_factor"
  };

  String _path(RequestOptions o) {
    final path = o.uri.path;
    final i = path.indexOf("/v2/");
    return i < 0 ? path : path.substring(i + 4);
  }

  String _keys(Object? data) {
    if (data is Map) {
      return "{${data.keys.map((k) => _sensitive.contains(k) ? "$k=***" : "$k").join(",")}}";
    }
    if (data is FormData) return "{form}";
    return "";
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra["diag_t0"] = DateTime.now().millisecondsSinceEpoch;
    Diagnostics.log(
        "http", "→ ${options.method} ${_path(options)} ${_keys(options.data)}");
    handler.next(options);
  }

  int _ms(RequestOptions o) {
    final t0 = o.extra["diag_t0"];
    return t0 is int ? DateTime.now().millisecondsSinceEpoch - t0 : -1;
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final data = response.data;
    final kind = data is List
        ? "Liste(${data.length})"
        : data is Map
            ? "Objekt{${data.keys.take(6).join(",")}}"
            : data is String
                ? (data.contains("window.location") &&
                        data.contains("/v2/login")
                    ? "UMLEITUNG ZUM LOGIN"
                    : "Text(${data.length})")
                : "${data.runtimeType}";
    var extra = "";
    if (data is Map) {
      for (final key in const [
        "loggedIn",
        "error",
        "forceLogout",
        "noSession",
        "success"
      ]) {
        if (data.containsKey(key)) extra += " $key=${data[key]}";
      }
    }
    Diagnostics.log("http",
        "← ${response.statusCode} ${_path(response.requestOptions)} ${_ms(response.requestOptions)}ms $kind$extra");
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final data = err.response?.data;
    Diagnostics.log("http",
        "✗ ${_path(err.requestOptions)} ${_ms(err.requestOptions)}ms ${Diagnostics.describeError(err)}${data is Map ? " body=$data" : ""}");
    handler.next(err);
  }
}
