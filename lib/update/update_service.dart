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

/// Checks for a newer version and installs it.
///
/// Two sources are understood, decided by what the address looks like:
///
///  * **GitHub releases** — `https://github.com/user/repo`. The latest release
///    is read through the GitHub API; the tag is the version and the assets are
///    the downloads, picked by file ending (`.exe`/`.msi` on Windows, `.apk` on
///    Android). This is the normal case.
///  * **A plain `latest.json`** — any other address, for serving releases from
///    somewhere without an API:
///
/// ```json
/// {
///   "version": "8.3.0",
///   "notes": "Was sich geändert hat …",
///   "builds": {
///     "windows": { "url": "https://…/setup.exe", "sha256": "…", "size": 13930000 },
///     "android": { "url": "https://…/app.apk",   "sha256": "…", "size": 66300000 }
///   }
/// }
/// ```
///
/// `sha256` and `size` are optional but checked when present — an update that
/// downloads a corrupted or substituted file must not be installed. GitHub does
/// not publish hashes through its API, so downloads from there are verified by
/// the transport (HTTPS) alone.
///
/// What "install" means depends on the platform:
///  * Windows: run the downloaded installer and quit, so it can replace files.
///  * Android: hand the APK to the system package installer.
///  * everything else: open the download page in the browser.
library;

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dr/file_opener.dart';
import 'package:dr/util.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A version like `8.2.15`, comparable to another one.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, this.raw);

  final List<int> parts;
  final String raw;

  /// Parses a version, ignoring anything after a `+` or `-` suffix.
  static AppVersion? tryParse(String? input) {
    if (input == null) return null;
    final cleaned = input.trim().split(RegExp(r"[+\-\s]")).first;
    if (cleaned.isEmpty) return null;
    final parts = <int>[];
    for (final piece in cleaned.split(".")) {
      final value = int.tryParse(piece);
      if (value == null) return null;
      parts.add(value);
    }
    if (parts.isEmpty) return null;
    return AppVersion(parts, cleaned);
  }

  @override
  int compareTo(AppVersion other) {
    final length =
        parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() => raw;
}

/// One downloadable build.
class UpdateBuild {
  const UpdateBuild({
    required this.url,
    this.sha256Hash,
    this.size,
  });

  final String url;
  final String? sha256Hash;
  final int? size;
}

/// What the release server offers.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.build,
  });

  final AppVersion version;
  final String? notes;

  /// The build for the platform we are running on, if the server has one.
  final UpdateBuild? build;
}

class UpdateService {
  const UpdateService();

  /// The key under which the release server lists the current platform.
  static String get platformKey {
    if (Platform.isWindows) return "windows";
    if (Platform.isAndroid) return "android";
    if (Platform.isMacOS) return "macos";
    if (Platform.isLinux) return "linux";
    if (Platform.isIOS) return "ios";
    return Platform.operatingSystem;
  }

  /// The file endings that count as an installable build, most preferred first.
  static List<String> get _platformExtensions {
    if (Platform.isWindows) return const [".exe", ".msi", ".zip"];
    if (Platform.isAndroid) return const [".apk"];
    if (Platform.isMacOS) return const [".dmg", ".pkg", ".zip"];
    if (Platform.isLinux) return const [".appimage", ".deb", ".tar.gz"];
    return const [];
  }

  /// Fetches the release description from [baseUrl].
  ///
  /// [baseUrl] may be a GitHub repository, a JSON document, or a directory in
  /// which case `latest.json` is appended. Returns null when nothing newer than
  /// [currentVersion] is offered, or when the server cannot be reached.
  Future<UpdateInfo?> check({
    required String baseUrl,
    String? currentVersion,
  }) async {
    if (baseUrl.trim().isEmpty) return null;
    final current = AppVersion.tryParse(currentVersion ?? appVersion);
    if (current == null) {
      log("cannot parse the running version, skipping the update check");
      return null;
    }

    final github = gitHubApiUri(baseUrl);
    final uri = github ?? _manifestUri(baseUrl);
    try {
      final response = await http.get(
        uri,
        headers: const {
          "Accept": "application/json",
          // GitHub answers 403 to requests without one.
          "User-Agent": "digitales-register-app",
        },
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        log("update check: server answered ${response.statusCode} for $uri");
        return null;
      }
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      final manifest = getMap(decoded);
      if (manifest == null) return null;

      final info = github == null
          ? _parseManifest(manifest)
          : _parseGitHubRelease(manifest);
      if (info == null || !info.version.isNewerThan(current)) return null;
      return info;
    } catch (e) {
      log("update check failed", error: e);
      return null;
    }
  }

  /// The GitHub API address for [input], or null when it is not a GitHub link.
  ///
  /// Accepts `https://github.com/user/repo`, the same with `/releases` or
  /// `/releases/latest` appended, and an API address that is already correct.
  static Uri? gitHubApiUri(String input) {
    var url = input.trim();
    if (url.isEmpty) return null;
    while (url.endsWith("/")) {
      url = url.substring(0, url.length - 1);
    }
    if (!RegExp(r"^[a-zA-Z][a-zA-Z0-9+.-]*://").hasMatch(url)) {
      url = "https://$url";
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();

    if (host == "api.github.com") {
      // Already an API address; use it as it is, but make sure it asks for a
      // release rather than something else.
      return uri.path.contains("/releases") ? uri : null;
    }
    if (host != "github.com" && host != "www.github.com") return null;

    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    var repo = segments[1];
    if (repo.toLowerCase().endsWith(".git")) {
      repo = repo.substring(0, repo.length - 4);
    }
    return Uri.https("api.github.com", "/repos/$owner/$repo/releases/latest");
  }

  static UpdateInfo? _parseGitHubRelease(Map<dynamic, dynamic> release) {
    // A draft would not be downloadable and a prerelease is not meant for
    // everyone, so neither is offered.
    if (getBool(release["draft"]) == true) return null;
    if (getBool(release["prerelease"]) == true) return null;

    // The tag is the version; a leading "v" is the usual convention.
    final tag = getString(release["tag_name"]) ?? getString(release["name"]);
    final version = AppVersion.tryParse(_stripTagPrefix(tag));
    if (version == null) return null;

    return UpdateInfo(
      version: version,
      notes: getString(release["body"]),
      build: _pickGitHubAsset(getList(release["assets"])),
    );
  }

  static String? _stripTagPrefix(String? tag) {
    if (tag == null) return null;
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.startsWith("v") || trimmed.startsWith("V")
        ? trimmed.substring(1)
        : trimmed;
  }

  /// The asset that fits this platform, by file ending.
  static UpdateBuild? _pickGitHubAsset(List<dynamic>? assets) {
    if (assets == null) return null;
    for (final extension in _platformExtensions) {
      for (final raw in assets) {
        final asset = getMap(raw);
        final name = getString(asset?["name"])?.toLowerCase();
        final url = getString(asset?["browser_download_url"]);
        if (name == null || url == null) continue;
        if (!name.endsWith(extension)) continue;
        return UpdateBuild(url: url, size: getInt(asset?["size"]));
      }
    }
    return null;
  }

  static UpdateInfo? _parseManifest(Map<dynamic, dynamic> manifest) {
    final version = AppVersion.tryParse(getString(manifest["version"]));
    if (version == null) return null;
    return UpdateInfo(
      version: version,
      notes: getString(manifest["notes"]),
      build: _parseBuild(manifest),
    );
  }

  static Uri _manifestUri(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith("/")) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.toLowerCase().endsWith(".json")) url = "$url/latest.json";
    return Uri.parse(url);
  }

  static UpdateBuild? _parseBuild(Map<dynamic, dynamic> manifest) {
    final builds = getMap(manifest["builds"]);
    final entry = getMap(builds?[platformKey]);
    final url = getString(entry?["url"]);
    if (url == null || url.isEmpty) return null;
    return UpdateBuild(
      url: url,
      sha256Hash: getString(entry?["sha256"]),
      size: getInt(entry?["size"]),
    );
  }

  /// Downloads [build] and hands it to the system.
  ///
  /// [onProgress] receives a value between 0 and 1 while downloading, or null
  /// when the server does not report a length. Returns null on success or a
  /// message to show the user.
  Future<String?> download(
    UpdateBuild build, {
    void Function(double? progress)? onProgress,
  }) async {
    final File file;
    try {
      file = await _downloadTo(build, onProgress);
    } catch (e) {
      log("update download failed", error: e);
      return "Der Download ist fehlgeschlagen.";
    }

    if (build.sha256Hash != null) {
      final actual = sha256.convert(await file.readAsBytes()).toString();
      if (actual.toLowerCase() != build.sha256Hash!.toLowerCase()) {
        await file.delete();
        log("update rejected: sha256 mismatch");
        return "Die heruntergeladene Datei ist beschädigt und wurde verworfen.";
      }
    }

    final result = await openFileWithDefaultApp(file.path);
    if (!result.success) return result.errorMessage;

    if (Platform.isWindows) {
      // The installer cannot replace files that are still in use, so step out
      // of the way once it is running.
      await Future<void>.delayed(const Duration(seconds: 2));
      exit(0);
    }
    return null;
  }

  Future<File> _downloadTo(
    UpdateBuild build,
    void Function(double? progress)? onProgress,
  ) async {
    final directory = await getTemporaryDirectory();
    final name = Uri.parse(build.url).pathSegments.last;
    final file = File(
      joinPath(directory.path, sanitizeFileName(name.isEmpty ? "update" : name)),
    );

    final client = http.Client();
    try {
      final request = http.Request("GET", Uri.parse(build.url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException("status ${response.statusCode}", uri: request.url);
      }
      final total = response.contentLength ?? build.size;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(total == null || total <= 0 ? null : received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Fallback for platforms without an in-app install path.
  Future<void> openInBrowser(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
