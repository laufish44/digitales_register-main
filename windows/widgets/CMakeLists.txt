# The widget provider: a small COM server Windows starts to fill the app's
# widgets (Widgets board and lock screen). See provider.cpp.
cmake_minimum_required(VERSION 3.14)
project(dr_widgets LANGUAGES CXX)

set(WIDGET_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party")
set(CPPWINRT_EXE "${WIDGET_SDK_DIR}/cppwinrt.exe")
set(WIDGETS_WINMD "${WIDGET_SDK_DIR}/Microsoft.Windows.Widgets.winmd")

if(NOT EXISTS "${CPPWINRT_EXE}" OR NOT EXISTS "${WIDGETS_WINMD}")
  message(WARNING "Windows widgets skipped: run tool/fetch_widget_sdk.ps1 first.")
  return()
endif()

# The C++/WinRT projection of the Windows SDK and the widget API, generated
# into the build folder once.
set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/cppwinrt")
if(NOT EXISTS "${GENERATED_DIR}/winrt/Microsoft.Windows.Widgets.Providers.h")
  execute_process(
    COMMAND "${CPPWINRT_EXE}" -input local -input "${WIDGETS_WINMD}"
            -output "${GENERATED_DIR}"
    RESULT_VARIABLE CPPWINRT_RESULT)
  if(NOT CPPWINRT_RESULT EQUAL 0)
    message(FATAL_ERROR "cppwinrt failed: ${CPPWINRT_RESULT}")
  endif()
endif()

add_executable(dr_widgets WIN32
  "provider.cpp"
  "dr_widgets.rc"
)
target_include_directories(dr_widgets PRIVATE "${GENERATED_DIR}")
target_compile_features(dr_widgets PRIVATE cxx_std_20)
target_compile_options(dr_widgets PRIVATE /EHsc /bigobj /permissive- /utf-8)
target_compile_definitions(dr_widgets PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(dr_widgets PRIVATE windowsapp ole32 shell32 gdiplus crypt32)
# The manifest comes from dr_widgets.rc, not from the linker.
target_link_options(dr_widgets PRIVATE /MANIFEST:NO)

install(TARGETS dr_widgets RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
