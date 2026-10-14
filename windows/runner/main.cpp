#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cstring>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The app's visible window, if it is already open. Set in win32_window.cpp;
// the background service's hidden window does not carry the property.
HWND FindOpenMainWindow() {
  HWND window = nullptr;
  while ((window = ::FindWindowExW(nullptr, window,
                                  L"FLUTTER_RUNNER_WIN32_WINDOW",
                                  nullptr)) != nullptr) {
    if (::GetPropW(window, L"DigitalesRegisterMainWindow") != nullptr) {
      return window;
    }
  }
  return nullptr;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // --background starts the headless notification service: same binary, same
  // Flutter engine (the plugins need it), but no visible window. See
  // lib/background/windows_background.dart.
  //
  // Compared through strcmp on purpose: Utf8FromUtf16 in utils.cpp converts
  // with a length of -1, which keeps the terminating null *inside* the
  // std::string. "--background\0" is 13 characters long, so comparing it to the
  // 12 character literal with == is always false.
  bool run_in_background =
      std::any_of(command_line_arguments.begin(), command_line_arguments.end(),
                  [](const std::string& argument) {
                    return std::strcmp(argument.c_str(), "--background") == 0;
                  });

  // One window is enough: starting the app again (from the start menu, or a
  // click on a notification) brings the open one to the front instead of
  // logging in a second time.
  if (!run_in_background) {
    if (HWND open_window = FindOpenMainWindow()) {
      if (::IsIconic(open_window)) {
        ::ShowWindow(open_window, SW_RESTORE);
      }
      ::SetForegroundWindow(open_window);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.CreateAndShow(L"Digitales Register", origin, size,
                            run_in_background)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
