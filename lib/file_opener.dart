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

/// Hands a downloaded attachment over to the application the operating system
/// has registered for its file type.
///
/// The `open_file`/`open_filex` package runs `Process.start("open", [path])`
/// for *both* macOS and Windows. `open` is a macOS command; Windows has no such
/// executable, so opening an attachment always failed there with
///
/// ```
/// ProcessException: The system cannot find the file specified.
///   Command: open "C:\Users\...\msg_263_141_Programm VWL.docx"
/// ```
///
/// The file Windows could not find is `open.exe`, not the attachment. On
/// Windows we therefore call `ShellExecuteW` — the very API Explorer uses when
/// you double click a file — directly through `dart:ffi`. Every other platform
/// keeps using the package, which is correct there (and on Android/iOS has to
/// go through the platform channel to build a `content://` URI).
library;

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:open_filex/open_filex.dart';

/// The outcome of [openFileWithDefaultApp].
class OpenFileResult {
  /// Whether the file was handed over to another application successfully.
  final bool success;

  /// A German message that can be shown to the user. `null` on success.
  final String? errorMessage;

  const OpenFileResult.success()
      : success = true,
        errorMessage = null;

  const OpenFileResult.failure(String this.errorMessage) : success = false;
}

/// Opens [path] with the default application for its file type.
///
/// Never throws: any failure is reported through the returned
/// [OpenFileResult] so that callers can show a message instead of tripping the
/// generic "Ein Fehler ist aufgetreten" error screen.
Future<OpenFileResult> openFileWithDefaultApp(String path) async {
  final normalized = normalizePath(path);
  log("opening file: $normalized");

  if (!File(normalized).existsSync()) {
    return const OpenFileResult.failure(
      "Die Datei wurde nicht gefunden. Bitte lade sie erneut herunter.",
    );
  }

  if (Platform.isWindows) {
    return _openOnWindows(normalized);
  }

  try {
    final result = await OpenFilex.open(normalized);
    if (result.type == ResultType.done) {
      return const OpenFileResult.success();
    }
    log("open_file failed for $normalized: ${result.type} ${result.message}");
    return OpenFileResult.failure(_describeOpenFileError(result.type));
  } catch (e) {
    log("failed to open $normalized", error: e);
    return const OpenFileResult.failure(
      "Die Datei konnte nicht geöffnet werden.",
    );
  }
}

String _describeOpenFileError(ResultType type) {
  switch (type) {
    case ResultType.fileNotFound:
      return "Die Datei wurde nicht gefunden. Bitte lade sie erneut herunter.";
    case ResultType.noAppToOpen:
      return "Für diesen Dateityp ist keine App installiert.";
    case ResultType.permissionDenied:
      return "Der Zugriff auf die Datei wurde verweigert.";
    case ResultType.error:
    case ResultType.done:
      return "Die Datei konnte nicht geöffnet werden.";
  }
}

/// Joins a directory and a file name with the separator of the current
/// platform.
String joinPath(String directory, String fileName) {
  final separator = Platform.isWindows ? r"\" : "/";
  final trimmed = directory.endsWith(separator) || directory.endsWith("/")
      ? directory.substring(0, directory.length - 1)
      : directory;
  return normalizePath("$trimmed$separator$fileName");
}

/// Rewrites path separators so that a path is spelled the way the current
/// platform expects it.
///
/// Most Windows APIs accept forward slashes, but some (notably `ShellExecute`
/// with a relative segment, and anything that displays the path to the user)
/// behave better with backslashes.
String normalizePath(String path) {
  if (Platform.isWindows) {
    return path.replaceAll("/", r"\");
  }
  return path;
}

/// Characters that Windows does not allow in a file name.
final _windowsReservedCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
final _posixReservedCharacters = RegExp(r'[/\x00]');

/// Makes [fileName] safe to use as a file name on the current platform.
///
/// The name is built from data the server sends us (see
/// `MessageAttachmentFile.uniqueName` and friends), so it can contain anything.
/// On Windows a name containing e.g. `:` cannot be created at all, and trailing
/// dots or spaces are silently stripped — which would make the file we wrote
/// and the file we later look for disagree.
///
/// Names that are already valid are returned unchanged, so attachments that
/// were downloaded by an earlier version of the app are still found.
String sanitizeFileName(String fileName) {
  var name = fileName.replaceAll(
    Platform.isWindows ? _windowsReservedCharacters : _posixReservedCharacters,
    "_",
  );
  if (Platform.isWindows) {
    // Windows strips trailing dots and spaces from file names.
    name = name.replaceFirst(RegExp(r'[. ]+$'), "");
  }
  if (name.isEmpty) {
    name = "download";
  }
  return name;
}

// ShellExecuteW returns a value greater than 32 on success; anything smaller
// is an error code.
const _shellExecuteSuccessThreshold = 32;
const _errorFileNotFound = 2;
const _errorPathNotFound = 3;
const _errorAccessDenied = 5;
const _seErrAssocIncomplete = 27;
const _seErrNoAssoc = 31;
const _swShowNormal = 1;

typedef _ShellExecuteWNative = IntPtr Function(
  IntPtr hwnd,
  Pointer<Utf16> operation,
  Pointer<Utf16> file,
  Pointer<Utf16> parameters,
  Pointer<Utf16> directory,
  Int32 showCmd,
);
typedef _ShellExecuteWDart = int Function(
  int hwnd,
  Pointer<Utf16> operation,
  Pointer<Utf16> file,
  Pointer<Utf16> parameters,
  Pointer<Utf16> directory,
  int showCmd,
);

_ShellExecuteWDart? _shellExecuteW;
var _triedLookingUpShellExecuteW = false;

_ShellExecuteWDart? _lookUpShellExecuteW() {
  if (_triedLookingUpShellExecuteW) return _shellExecuteW;
  _triedLookingUpShellExecuteW = true;
  try {
    _shellExecuteW = DynamicLibrary.open("shell32.dll")
        .lookupFunction<_ShellExecuteWNative, _ShellExecuteWDart>(
      "ShellExecuteW",
    );
  } catch (e) {
    log("failed to look up ShellExecuteW", error: e);
  }
  return _shellExecuteW;
}

int _shellExecute(_ShellExecuteWDart shellExecuteW, String path, String verb) {
  final verbPointer = verb.toNativeUtf16();
  final pathPointer = path.toNativeUtf16();
  try {
    return shellExecuteW(
      0,
      verbPointer,
      pathPointer,
      nullptr,
      nullptr,
      _swShowNormal,
    );
  } finally {
    malloc.free(verbPointer);
    malloc.free(pathPointer);
  }
}

Future<OpenFileResult> _openOnWindows(String path) async {
  final shellExecuteW = _lookUpShellExecuteW();
  if (shellExecuteW == null) {
    // shell32.dll is always present, so this should not happen. If it somehow
    // does we can still ask Explorer to open the file for us.
    return _openWithExplorer(path);
  }

  var code = _shellExecute(shellExecuteW, path, "open");
  if (code > _shellExecuteSuccessThreshold) {
    return const OpenFileResult.success();
  }

  if (code == _seErrNoAssoc || code == _seErrAssocIncomplete) {
    // Nothing is registered for this file type. Show the "Wie möchtest du
    // diese Datei öffnen?" picker instead of failing, which is what Explorer
    // does on a double click as well.
    code = _shellExecute(shellExecuteW, path, "openas");
    if (code > _shellExecuteSuccessThreshold) {
      return const OpenFileResult.success();
    }
  }

  log("ShellExecuteW failed for $path with code $code");
  return OpenFileResult.failure(_describeWindowsError(code));
}

String _describeWindowsError(int code) {
  switch (code) {
    case _errorFileNotFound:
    case _errorPathNotFound:
      return "Die Datei wurde nicht gefunden. Bitte lade sie erneut herunter.";
    case _errorAccessDenied:
      return "Der Zugriff auf die Datei wurde verweigert.";
    case _seErrNoAssoc:
    case _seErrAssocIncomplete:
      return "Für diesen Dateityp ist kein Programm installiert.";
    default:
      return "Die Datei konnte nicht geöffnet werden (Fehlercode $code).";
  }
}

Future<OpenFileResult> _openWithExplorer(String path) async {
  try {
    // explorer.exe reports a non-zero exit code even when it succeeds, so we
    // cannot tell success and failure apart here.
    await Process.start("explorer.exe", [path]);
    return const OpenFileResult.success();
  } catch (e) {
    log("failed to launch explorer.exe for $path", error: e);
    return const OpenFileResult.failure(
      "Die Datei konnte nicht geöffnet werden.",
    );
  }
}
