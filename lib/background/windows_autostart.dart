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

/// Makes Windows start the background service when the user logs in.
///
/// This writes to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, the
/// per-user autostart list that users can inspect and disable in the Task
/// Manager's "Autostart" tab. It needs no administrator rights and touches
/// nothing outside the current user's own registry hive.
///
/// The registry is used through `dart:ffi` rather than `reg.exe` so that no
/// console window flashes up when the setting is toggled.
library;

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The command line switch that makes `main()` run headless.
const backgroundModeFlag = "--background";

const _runKeyPath =
    r"Software\Microsoft\Windows\CurrentVersion\Run";
const _valueName = "DigitalesRegister";

const _hkeyCurrentUser = 0x80000001;
const _keyQueryValue = 0x0001;
const _keySetValue = 0x0002;
const _standardRightsRead = 0x00020000;
const _errorSuccess = 0;
const _regSz = 1;

typedef _RegOpenKeyExWNative = Int32 Function(
    IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _RegOpenKeyExWDart = int Function(
    int, Pointer<Utf16>, int, int, Pointer<IntPtr>);

typedef _RegSetValueExWNative = Int32 Function(
    IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>, Uint32);
typedef _RegSetValueExWDart = int Function(
    int, Pointer<Utf16>, int, int, Pointer<Uint8>, int);

typedef _RegQueryValueExWNative = Int32 Function(IntPtr, Pointer<Utf16>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _RegQueryValueExWDart = int Function(int, Pointer<Utf16>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);

typedef _RegDeleteValueWNative = Int32 Function(IntPtr, Pointer<Utf16>);
typedef _RegDeleteValueWDart = int Function(int, Pointer<Utf16>);

typedef _RegCloseKeyNative = Int32 Function(IntPtr);
typedef _RegCloseKeyDart = int Function(int);

class WindowsAutostart {
  WindowsAutostart._();

  static DynamicLibrary? _advapi32;
  static DynamicLibrary? get _lib {
    if (!Platform.isWindows) return null;
    try {
      return _advapi32 ??= DynamicLibrary.open("advapi32.dll");
    } catch (e) {
      log("failed to open advapi32.dll", error: e);
      return null;
    }
  }

  /// The command Windows should run at logon.
  static String get command => '"${Platform.resolvedExecutable}" $backgroundModeFlag';

  /// Whether the background service is registered to start at logon.
  static Future<bool> isEnabled() async {
    final lib = _lib;
    if (lib == null) return false;
    return _withRunKey(lib, _standardRightsRead | _keyQueryValue, (key) {
          final query = lib.lookupFunction<_RegQueryValueExWNative,
              _RegQueryValueExWDart>("RegQueryValueExW");
          final namePointer = _valueName.toNativeUtf16();
          try {
            return query(key, namePointer, nullptr, nullptr, nullptr,
                    nullptr) ==
                _errorSuccess;
          } finally {
            malloc.free(namePointer);
          }
        }) ??
        false;
  }

  /// Adds or removes the autostart entry. Returns true on success.
  static Future<bool> setEnabled(bool enabled) async {
    final lib = _lib;
    if (lib == null) return false;
    return _withRunKey(lib, _standardRightsRead | _keySetValue, (key) {
          final namePointer = _valueName.toNativeUtf16();
          try {
            if (!enabled) {
              final delete = lib.lookupFunction<_RegDeleteValueWNative,
                  _RegDeleteValueWDart>("RegDeleteValueW");
              final result = delete(key, namePointer);
              // Deleting something that is not there is not a failure.
              return result == _errorSuccess || result == 2;
            }

            final set = lib.lookupFunction<_RegSetValueExWNative,
                _RegSetValueExWDart>("RegSetValueExW");
            final value = command;
            final valuePointer = value.toNativeUtf16();
            try {
              // REG_SZ data is the UTF-16 string including its null terminator.
              final byteCount = (value.length + 1) * 2;
              return set(key, namePointer, 0, _regSz,
                      valuePointer.cast<Uint8>(), byteCount) ==
                  _errorSuccess;
            } finally {
              malloc.free(valuePointer);
            }
          } finally {
            malloc.free(namePointer);
          }
        }) ??
        false;
  }

  /// Opens the Run key, runs [action] and always closes the key again.
  static T? _withRunKey<T>(
    DynamicLibrary lib,
    int access,
    T Function(int key) action,
  ) {
    final open = lib.lookupFunction<_RegOpenKeyExWNative, _RegOpenKeyExWDart>(
        "RegOpenKeyExW");
    final close =
        lib.lookupFunction<_RegCloseKeyNative, _RegCloseKeyDart>("RegCloseKey");

    final pathPointer = _runKeyPath.toNativeUtf16();
    final keyPointer = calloc<IntPtr>();
    try {
      if (open(_hkeyCurrentUser, pathPointer, 0, access, keyPointer) !=
          _errorSuccess) {
        log("failed to open the autostart registry key");
        return null;
      }
      final key = keyPointer.value;
      try {
        return action(key);
      } finally {
        close(key);
      }
    } catch (e, trace) {
      log("autostart registry access failed", error: e, stackTrace: trace);
      return null;
    } finally {
      malloc.free(pathPointer);
      calloc.free(keyPointer);
    }
  }
}
