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

/// Opening the app from a Windows notification.
///
/// A click on a toast reaches whichever of our processes registered the
/// notification plugin's COM class — very often the hidden background service,
/// which has nothing to show. So the click is turned into "bring the app's
/// window to the front, or start the app" here, from either process.
library;

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Set on the visible window only, by windows/runner/win32_window.cpp. The
/// hidden window of the background service has the same class and title.
const _mainWindowProperty = "DigitalesRegisterMainWindow";
const _windowClass = "FLUTTER_RUNNER_WIN32_WINDOW";

const _swRestore = 9;
const _asfwAny = 0xFFFFFFFF;
const _regSz = 1;

/// `HKEY_CURRENT_USER`, sign-extended the way the Windows headers define it.
const _hkeyCurrentUser = -2147483647;

final _user32 = DynamicLibrary.open("user32.dll");
final _advapi32 = DynamicLibrary.open("advapi32.dll");

final _findWindowEx = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
    int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>("FindWindowExW");
final _getProp = _user32.lookupFunction<IntPtr Function(IntPtr, Pointer<Utf16>),
    int Function(int, Pointer<Utf16>)>("GetPropW");
final _isIconic = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>("IsIconic");
final _showWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32),
    int Function(int, int)>("ShowWindow");
final _setForegroundWindow =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        "SetForegroundWindow");
final _allowSetForegroundWindow =
    _user32.lookupFunction<Int32 Function(Uint32), int Function(int)>(
        "AllowSetForegroundWindow");
final _regSetKeyValue = _advapi32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>, Uint32),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>,
        int)>("RegSetKeyValueW");

/// The app's visible window, or 0 when the app is not open.
int _findMainWindow() {
  return using((arena) {
    final windowClass = _windowClass.toNativeUtf16(allocator: arena);
    final property = _mainWindowProperty.toNativeUtf16(allocator: arena);
    var window = 0;
    while (true) {
      window = _findWindowEx(0, window, windowClass, nullptr);
      if (window == 0) return 0;
      if (_getProp(window, property) != 0) return window;
    }
  });
}

/// Brings the app to the front, starting it when it is not open.
///
/// Called when a notification is clicked. Never throws.
Future<void> showMainApp() async {
  if (!Platform.isWindows) return;
  try {
    final window = _findMainWindow();
    if (window != 0) {
      if (_isIconic(window) != 0) _showWindow(window, _swRestore);
      _setForegroundWindow(window);
      return;
    }
    // The click gave this process the right to take the foreground; pass it
    // on to the app it is about to start.
    _allowSetForegroundWindow(_asfwAny);
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      mode: ProcessStartMode.detached,
    );
  } catch (e, trace) {
    log("could not open the app from a notification",
        error: e, stackTrace: trace);
  }
}

/// Tells Windows which program to start for a click on one of our
/// notifications when none of our processes is running.
///
/// The notification plugin only registers its activator while a process is
/// alive; without `LocalServer32` a click on a toast left in the action centre
/// did nothing at all. Windows appends `-Embedding` to the command line, which
/// the runner ignores, so the app simply opens.
void registerNotificationActivator(String guid) {
  if (!Platform.isWindows) return;
  try {
    using((arena) {
      final key = "Software\\Classes\\CLSID\\{$guid}\\LocalServer32"
          .toNativeUtf16(allocator: arena);
      final command = '"${Platform.resolvedExecutable}"';
      final data = command.toNativeUtf16(allocator: arena);
      final result = _regSetKeyValue(
        _hkeyCurrentUser,
        key,
        nullptr,
        _regSz,
        data.cast(),
        (command.length + 1) * 2,
      );
      if (result != 0) log("registering the notification activator: $result");
    });
  } catch (e, trace) {
    log("could not register the notification activator",
        error: e, stackTrace: trace);
  }
}
