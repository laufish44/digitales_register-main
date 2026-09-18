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

import 'dart:ffi';
import 'dart:io';

import 'package:dr/file_actions.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the file names back off the Windows clipboard, so the test checks what
/// other programs would actually see rather than what we think we wrote.
List<String> _readClipboardFiles() {
  final user32 = DynamicLibrary.open("user32.dll");
  final shell32 = DynamicLibrary.open("shell32.dll");

  final openClipboard = user32.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>("OpenClipboard");
  final closeClipboard =
      user32.lookupFunction<Int32 Function(), int Function()>("CloseClipboard");
  final getClipboardData = user32.lookupFunction<
      Pointer<Void> Function(Uint32),
      Pointer<Void> Function(int)>("GetClipboardData");
  final isFormatAvailable = user32.lookupFunction<Int32 Function(Uint32),
      int Function(int)>("IsClipboardFormatAvailable");
  final dragQueryFile = shell32.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32, Pointer<Utf16>, Uint32),
      int Function(Pointer<Void>, int, Pointer<Utf16>, int)>("DragQueryFileW");

  const cfHdrop = 15;
  if (isFormatAvailable(cfHdrop) == 0) return const [];
  if (openClipboard(nullptr) == 0) return const [];
  try {
    final handle = getClipboardData(cfHdrop);
    if (handle == nullptr) return const [];
    final count = dragQueryFile(handle, 0xFFFFFFFF, nullptr, 0);
    final buffer = calloc<Uint16>(1024).cast<Utf16>();
    try {
      return [
        for (var i = 0; i < count; i++)
          if (dragQueryFile(handle, i, buffer, 1024) > 0) buffer.toDartString(),
      ];
    } finally {
      calloc.free(buffer);
    }
  } finally {
    closeClipboard();
  }
}

void main() {
  group("Win32 struct layouts", () {
    test("OPENFILENAMEW is the size comdlg32 expects", () {
      // 152 bytes on 64 bit Windows. Getting this wrong makes
      // GetSaveFileNameW fail silently - it just returns without a dialog.
      expect(openFileNameStructSize, sizeOf<IntPtr>() == 8 ? 152 : 88);
    }, skip: !Platform.isWindows);

    test("DROPFILES is twenty bytes", () {
      // The file names start right after the header, which is why the header
      // size is also the offset written into pFiles.
      expect(dropFilesStructSize, 20);
    }, skip: !Platform.isWindows);
  });

  group("clipboard", () {
    test("puts a real file on the clipboard", () async {
      final directory = Directory.systemTemp.createTempSync("dr_clip");
      final file = File("${directory.path}\\Anhang Test.txt")
        ..writeAsStringSync("hallo");
      try {
        final result = await copyFileToClipboard(file.path);
        expect(result.success, isTrue, reason: result.message);

        final onClipboard = _readClipboardFiles();
        expect(onClipboard, hasLength(1));
        // Compared case insensitively: Windows hands the path back in its own
        // spelling.
        expect(
          onClipboard.single.toLowerCase(),
          file.path.toLowerCase(),
        );
      } finally {
        directory.deleteSync(recursive: true);
      }
    }, skip: !Platform.isWindows);

    test("says so when the file is gone", () async {
      final result = await copyFileToClipboard(
          "${Directory.systemTemp.path}\\gibt-es-nicht-12345.txt");
      expect(result.success, isFalse);
      expect(result.message, isNotNull);
    }, skip: !Platform.isWindows);
  });

  group("platform support", () {
    test("Windows has both a save dialog and a file clipboard", () {
      expect(hasSaveAsDialog, isTrue);
      expect(canCopyFileToClipboard, isTrue);
    }, skip: !Platform.isWindows);
  });

  group("saving", () {
    test("refuses a file that is not there", () async {
      final result = await saveFileAs(
          "${Directory.systemTemp.path}${Platform.pathSeparator}nope-98765.txt");
      expect(result.success, isFalse);
      expect(result.cancelled, isFalse);
      expect(result.message, contains("nicht gefunden"));
    });
  });
}
