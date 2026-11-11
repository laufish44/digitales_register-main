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
const _wmClose = 0x0010;
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
final _postMessage = _user32.lookupFunction<
    Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>("PostMessageW");
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

/// Closes the app's window the way its close button does (#14: Ctrl+W), so
/// everything that happens on closing still happens.
void closeMainWindow() {
  if (!Platform.isWindows) return;
  try {
    final window = _findMainWindow();
    if (window != 0) _postMessage(window, _wmClose, 0, 0);
  } catch (e, trace) {
    log("could not close the window", error: e, stackTrace: trace);
  }
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

// The mini window (23 of the 9.0 list): the app's own window, made small,
// without a frame and always on top, in the bottom right corner.

const _gwlStyle = -16;
const _wsCaption = 0x00C00000;
const _wsThickFrame = 0x00040000;
const _wsMinimizeBox = 0x00020000;
const _wsMaximizeBox = 0x00010000;
const _swpFrameChanged = 0x0020;
const _swpShowWindow = 0x0040;
const _hwndTopmost = -1;
const _hwndNoTopmost = -2;
const _spiGetWorkArea = 0x0030;
const _wmNcLButtonDown = 0x00A1;
const _htCaption = 2;
const _miniProperty = "DigitalesRegisterMini";

final _getWindowLongPtr = _user32.lookupFunction<IntPtr Function(IntPtr, Int32),
    int Function(int, int)>("GetWindowLongPtrW");
final _setWindowLongPtr = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32, IntPtr),
    int Function(int, int, int)>("SetWindowLongPtrW");
final _getWindowRect = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Int32>),
    int Function(int, Pointer<Int32>)>("GetWindowRect");
final _setWindowPos = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>("SetWindowPos");
final _systemParametersInfo = _user32.lookupFunction<
    Int32 Function(Uint32, Uint32, Pointer<Int32>, Uint32),
    int Function(int, int, Pointer<Int32>, int)>("SystemParametersInfoW");
final _getDpiForWindow =
    _user32.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
        "GetDpiForWindow");
final _isZoomed = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>("IsZoomed");
final _setProp = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, IntPtr),
    int Function(int, Pointer<Utf16>, int)>("SetPropW");
final _removeProp = _user32.lookupFunction<
    IntPtr Function(IntPtr, Pointer<Utf16>),
    int Function(int, Pointer<Utf16>)>("RemovePropW");
final _releaseCapture =
    _user32.lookupFunction<Int32 Function(), int Function()>("ReleaseCapture");
final _sendMessage = _user32.lookupFunction<
    IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>("SendMessageW");

/// How the window was before it turned into the mini window.
({
  int style,
  int left,
  int top,
  int width,
  int height,
  bool maximized
})? _beforeMini;

/// Turns the app's window into the mini window: [width] × [height] logical
/// pixels, no frame, always on top, bottom right. Returns false if that did
/// not work (or this is not Windows).
bool enterMiniWindow({int width = 360, int height = 132}) {
  if (!Platform.isWindows || _beforeMini != null) return false;
  try {
    final window = _findMainWindow();
    if (window == 0) return false;
    return using((arena) {
      final maximized = _isZoomed(window) != 0;
      if (maximized) _showWindow(window, _swRestore);
      final rect = arena<Int32>(4);
      _getWindowRect(window, rect);
      final style = _getWindowLongPtr(window, _gwlStyle);
      _beforeMini = (
        style: style,
        left: rect[0],
        top: rect[1],
        width: rect[2] - rect[0],
        height: rect[3] - rect[1],
        maximized: maximized,
      );
      _setProp(window, _miniProperty.toNativeUtf16(allocator: arena), 1);
      _setWindowLongPtr(
        window,
        _gwlStyle,
        style & ~(_wsCaption | _wsThickFrame | _wsMinimizeBox | _wsMaximizeBox),
      );
      final scale = _getDpiForWindow(window) / 96;
      final w = (width * scale).round(), h = (height * scale).round();
      final work = arena<Int32>(4);
      _systemParametersInfo(_spiGetWorkArea, 0, work, 0);
      final margin = (16 * scale).round();
      _setWindowPos(window, _hwndTopmost, work[2] - w - margin,
          work[3] - h - margin, w, h, _swpFrameChanged | _swpShowWindow);
      return true;
    });
  } catch (e, trace) {
    log("could not open the mini window", error: e, stackTrace: trace);
    return false;
  }
}

/// Puts the window back the way it was.
void leaveMiniWindow() {
  final before = _beforeMini;
  if (!Platform.isWindows || before == null) return;
  _beforeMini = null;
  try {
    final window = _findMainWindow();
    if (window == 0) return;
    using((arena) {
      _removeProp(window, _miniProperty.toNativeUtf16(allocator: arena));
    });
    _setWindowLongPtr(window, _gwlStyle, before.style);
    _setWindowPos(window, _hwndNoTopmost, before.left, before.top, before.width,
        before.height, _swpFrameChanged | _swpShowWindow);
    if (before.maximized) _showWindow(window, 3); // SW_MAXIMIZE
    _setForegroundWindow(window);
  } catch (e, trace) {
    log("could not leave the mini window", error: e, stackTrace: trace);
  }
}

/// Lets the user move the frameless mini window by dragging it: hands the
/// pressed mouse button over to Windows as if the title bar was grabbed.
void startWindowDrag() {
  if (!Platform.isWindows) return;
  try {
    final window = _findMainWindow();
    if (window == 0) return;
    _releaseCapture();
    _sendMessage(window, _wmNcLButtonDown, _htCaption, 0);
  } catch (e) {
    log("could not move the window", error: e);
  }
}
