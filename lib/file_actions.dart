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

/// What can be done with a downloaded attachment besides opening it:
/// saving it somewhere the user picks, and putting it on the clipboard.
///
/// Both are native operations with no Flutter plugin in this project, so they
/// are called through `dart:ffi` on Windows — the same approach
/// `file_opener.dart` already takes for `ShellExecuteW`. On Android there is no
/// "save as" dialog and no file clipboard; the share sheet is the system's own
/// answer to "put this file somewhere", so that is what is offered there.
library;

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

import 'package:dr/file_opener.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:share_plus/share_plus.dart';

/// The outcome of one of the actions below.
class FileActionResult {
  const FileActionResult.success([this.message])
      : success = true,
        cancelled = false;
  const FileActionResult.cancelled()
      : success = false,
        cancelled = true,
        message = null;
  const FileActionResult.failure(String this.message)
      : success = false,
        cancelled = false;

  final bool success;

  /// The user closed the dialog. Not an error, and nothing should be shown.
  final bool cancelled;

  /// A German message for the user, if there is anything worth saying.
  final String? message;
}

/// Whether a real "save as" dialog can be shown, as opposed to the share sheet.
bool get hasSaveAsDialog => Platform.isWindows;

/// Whether a file can be put on the clipboard on this platform.
///
/// Windows has a documented clipboard format for files (`CF_HDROP`). Android
/// would need a `FileProvider` and a platform channel on the Kotlin side, which
/// this app does not have, so the button is hidden there rather than pretending.
bool get canCopyFileToClipboard => Platform.isWindows;

/// Asks the user where to put [sourcePath] and copies it there.
///
/// On platforms without a save dialog the system share sheet is opened instead,
/// which offers "in Dateien sichern" and everything else the device can do with
/// a file.
Future<FileActionResult> saveFileAs(
  String sourcePath, {
  String? suggestedName,
}) async {
  final source = File(normalizePath(sourcePath));
  if (!source.existsSync()) {
    return const FileActionResult.failure(
      "Die Datei wurde nicht gefunden. Bitte lade sie erneut herunter.",
    );
  }

  final name = suggestedName ?? _baseName(source.path);

  if (!hasSaveAsDialog) {
    return _shareFile(source, name);
  }

  final String? target;
  try {
    target = _askWhereToSave(name);
  } catch (e, trace) {
    log("save dialog failed", error: e, stackTrace: trace);
    return const FileActionResult.failure(
      "Das Fenster zum Speichern konnte nicht geöffnet werden.",
    );
  }
  if (target == null) return const FileActionResult.cancelled();

  try {
    await source.copy(target);
    return FileActionResult.success("Gespeichert: ${_baseName(target)}");
  } catch (e) {
    log("failed to copy $sourcePath to $target", error: e);
    return const FileActionResult.failure(
      "Die Datei konnte nicht gespeichert werden.",
    );
  }
}

Future<FileActionResult> _shareFile(File source, String name) async {
  try {
    await Share.shareXFiles([XFile(source.path, name: name)], subject: name);
    return const FileActionResult.success();
  } catch (e) {
    log("failed to share ${source.path}", error: e);
    return const FileActionResult.failure(
      "Die Datei konnte nicht weitergegeben werden.",
    );
  }
}

/// Puts the file at [path] on the clipboard, so it can be pasted into Explorer,
/// an e-mail or a document.
Future<FileActionResult> copyFileToClipboard(String path) async {
  if (!canCopyFileToClipboard) {
    return const FileActionResult.failure(
      "Auf diesem Gerät können keine Dateien kopiert werden.",
    );
  }
  final file = File(normalizePath(path));
  if (!file.existsSync()) {
    return const FileActionResult.failure(
      "Die Datei wurde nicht gefunden. Bitte lade sie erneut herunter.",
    );
  }
  try {
    final ok = _putFileOnWindowsClipboard(file.path);
    return ok
        ? const FileActionResult.success("In die Zwischenablage kopiert")
        : const FileActionResult.failure(
            "Die Datei konnte nicht kopiert werden.",
          );
  } catch (e, trace) {
    log("failed to copy file to clipboard", error: e, stackTrace: trace);
    return const FileActionResult.failure(
      "Die Datei konnte nicht kopiert werden.",
    );
  }
}

String _baseName(String path) {
  final normalized = path.replaceAll(r"\", "/");
  final index = normalized.lastIndexOf("/");
  return index < 0 ? normalized : normalized.substring(index + 1);
}

// ---------------------------------------------------------------------------
// Windows: the "Speichern unter" dialog
// ---------------------------------------------------------------------------

/// `OPENFILENAMEW`. The field order is the layout — Dart applies the same
/// natural alignment the C compiler does, so this matches what comdlg32
/// expects as long as nothing is reordered.
final class _OpenFileNameW extends Struct {
  @Uint32()
  external int lStructSize;
  external Pointer<Void> hwndOwner;
  external Pointer<Void> hInstance;
  external Pointer<Utf16> lpstrFilter;
  external Pointer<Utf16> lpstrCustomFilter;
  @Uint32()
  external int nMaxCustFilter;
  @Uint32()
  external int nFilterIndex;
  external Pointer<Utf16> lpstrFile;
  @Uint32()
  external int nMaxFile;
  external Pointer<Utf16> lpstrFileTitle;
  @Uint32()
  external int nMaxFileTitle;
  external Pointer<Utf16> lpstrInitialDir;
  external Pointer<Utf16> lpstrTitle;
  @Uint32()
  external int flags;
  @Uint16()
  external int nFileOffset;
  @Uint16()
  external int nFileExtension;
  external Pointer<Utf16> lpstrDefExt;
  @IntPtr()
  external int lCustData;
  external Pointer<Void> lpfnHook;
  external Pointer<Utf16> lpTemplateName;
  external Pointer<Void> pvReserved;
  @Uint32()
  external int dwReserved;
  @Uint32()
  external int flagsEx;
}

/// The sizes comdlg32 and shell32 expect, exposed so a test can check that the
/// structs above still line up. A wrong size is the one mistake here that
/// produces no error, just a dialog that never appears.
@visibleForTesting
int get openFileNameStructSize => sizeOf<_OpenFileNameW>();
@visibleForTesting
int get dropFilesStructSize => sizeOf<_DropFiles>();

const _ofnOverwritePrompt = 0x00000002;
const _ofnPathMustExist = 0x00000800;
const _ofnNoChangeDir = 0x00000008;
const _ofnExplorer = 0x00080000;

/// Longest path the dialog may hand back.
const _maxPath = 32768;

typedef _GetSaveFileNameNative = Int32 Function(Pointer<_OpenFileNameW>);
typedef _GetSaveFileNameDart = int Function(Pointer<_OpenFileNameW>);

/// Shows the dialog and returns the chosen path, or null when it was cancelled.
String? _askWhereToSave(String suggestedName) {
  final getSaveFileName = DynamicLibrary.open("comdlg32.dll")
      .lookupFunction<_GetSaveFileNameNative, _GetSaveFileNameDart>(
    "GetSaveFileNameW",
  );

  final struct = calloc<_OpenFileNameW>();
  final buffer = calloc<Uint16>(_maxPath + 1).cast<Utf16>();
  final title = "Anhang speichern".toNativeUtf16();

  // The extension of the suggested name becomes the default one, so a name
  // typed without an extension still gets the right one.
  final extension = _extensionOf(suggestedName);
  final defExt = extension == null ? nullptr : extension.toNativeUtf16();

  // A filter of "Alle Dateien" keeps the dialog from hiding the very file type
  // we are saving. Each entry is null terminated, the list itself twice.
  final filter = _doubleNullTerminated(["Alle Dateien (*.*)", "*.*"]);

  try {
    _writeUtf16(buffer, suggestedName, _maxPath);

    struct.ref
      ..lStructSize = sizeOf<_OpenFileNameW>()
      ..lpstrFile = buffer
      ..nMaxFile = _maxPath
      ..lpstrTitle = title
      ..lpstrFilter = filter
      ..nFilterIndex = 1
      ..lpstrDefExt = defExt.cast()
      ..flags = _ofnOverwritePrompt |
          _ofnPathMustExist |
          _ofnNoChangeDir |
          _ofnExplorer;

    final ok = getSaveFileName(struct);
    if (ok == 0) return null; // cancelled, or an error we cannot act on
    return struct.ref.lpstrFile.toDartString();
  } finally {
    calloc.free(struct);
    calloc.free(buffer);
    calloc.free(title);
    calloc.free(filter);
    if (defExt != nullptr) calloc.free(defExt);
  }
}

String? _extensionOf(String name) {
  final dot = name.lastIndexOf(".");
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1);
}

/// Writes [value] into [buffer] as UTF-16, null terminated and truncated to
/// [maxUnits] code units including the terminator.
void _writeUtf16(Pointer<Utf16> buffer, String value, int maxUnits) {
  final units = value.codeUnits;
  final words = buffer.cast<Uint16>();
  final count = units.length < maxUnits - 1 ? units.length : maxUnits - 1;
  for (var i = 0; i < count; i++) {
    words[i] = units[i];
  }
  words[count] = 0;
}

/// The `"a\0b\0\0"` form the Win32 dialogs want for their lists.
Pointer<Utf16> _doubleNullTerminated(List<String> entries) {
  var length = 1; // the final extra terminator
  for (final entry in entries) {
    length += entry.codeUnits.length + 1;
  }
  final pointer = calloc<Uint16>(length);
  var offset = 0;
  for (final entry in entries) {
    for (final unit in entry.codeUnits) {
      pointer[offset++] = unit;
    }
    pointer[offset++] = 0;
  }
  pointer[offset] = 0;
  return pointer.cast<Utf16>();
}

// ---------------------------------------------------------------------------
// Windows: putting a file on the clipboard
// ---------------------------------------------------------------------------

/// `DROPFILES`, the header of a `CF_HDROP` clipboard block. The file names
/// follow it directly, which is why `pFiles` is simply its own size.
final class _DropFiles extends Struct {
  @Uint32()
  external int pFiles;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int fNC;
  @Int32()
  external int fWide;
}

const _cfHdrop = 15;
const _gmemMoveable = 0x0002;

bool _putFileOnWindowsClipboard(String path) {
  final user32 = DynamicLibrary.open("user32.dll");
  final kernel32 = DynamicLibrary.open("kernel32.dll");

  final openClipboard =
      user32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
          "OpenClipboard");
  final emptyClipboard =
      user32.lookupFunction<Int32 Function(), int Function()>("EmptyClipboard");
  final setClipboardData = user32.lookupFunction<
      Pointer<Void> Function(Uint32, Pointer<Void>),
      Pointer<Void> Function(int, Pointer<Void>)>("SetClipboardData");
  final closeClipboard =
      user32.lookupFunction<Int32 Function(), int Function()>("CloseClipboard");

  final globalAlloc = kernel32.lookupFunction<
      Pointer<Void> Function(Uint32, IntPtr),
      Pointer<Void> Function(int, int)>("GlobalAlloc");
  final globalLock = kernel32.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>("GlobalLock");
  final globalUnlock = kernel32.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>("GlobalUnlock");
  final globalFree = kernel32.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>("GlobalFree");

  final units = path.codeUnits;
  final headerSize = sizeOf<_DropFiles>();
  // The list of names ends with an empty name, so two terminators follow.
  final totalSize = headerSize + (units.length + 2) * 2;

  final handle = globalAlloc(_gmemMoveable, totalSize);
  if (handle == nullptr) return false;

  var ownsHandle = true;
  try {
    final block = globalLock(handle);
    if (block == nullptr) return false;
    try {
      final header = block.cast<_DropFiles>();
      header.ref
        ..pFiles = headerSize
        ..x = 0
        ..y = 0
        ..fNC = 0
        // Wide characters, because the path came from Dart as UTF-16.
        ..fWide = 1;

      final names = Pointer<Uint16>.fromAddress(block.address + headerSize);
      for (var i = 0; i < units.length; i++) {
        names[i] = units[i];
      }
      names[units.length] = 0;
      names[units.length + 1] = 0;
    } finally {
      globalUnlock(handle);
    }

    if (openClipboard(nullptr) == 0) return false;
    try {
      emptyClipboard();
      if (setClipboardData(_cfHdrop, handle) == nullptr) return false;
      // The clipboard owns the block now; freeing it would corrupt it.
      ownsHandle = false;
      return true;
    } finally {
      closeClipboard();
    }
  } finally {
    if (ownsHandle) globalFree(handle);
  }
}
