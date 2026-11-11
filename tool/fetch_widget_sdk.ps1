# Fetches what the Windows widget provider (windows/widgets) is built with:
# the C++/WinRT code generator and the metadata of the widget API from the
# Windows App SDK. Both come from nuget.org and are not part of the repository
# (the Windows App SDK is under Microsoft's own licence terms).
#
# Run once before `flutter build windows`; the build skips the widgets with a
# warning when they are missing.

$ErrorActionPreference = "Stop"
$target = Join-Path $PSScriptRoot "..\windows\widgets\third_party"
New-Item -ItemType Directory -Force $target | Out-Null
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "dr-widget-sdk"
New-Item -ItemType Directory -Force $temp | Out-Null

function Fetch($id, $version) {
    $zip = Join-Path $temp "$id.$version.zip"
    if (-not (Test-Path $zip)) {
        Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg" -OutFile $zip
    }
    $dir = Join-Path $temp "$id.$version"
    if (-not (Test-Path $dir)) { Expand-Archive $zip $dir -Force }
    return $dir
}

$cppwinrt = Fetch "microsoft.windows.cppwinrt" "2.0.250303.1"
Copy-Item (Join-Path $cppwinrt "bin\cppwinrt.exe") $target -Force

# 1.8: the runtime the widget package depends on (Microsoft.WindowsAppRuntime.1.8).
$widgets = Fetch "microsoft.windowsappsdk.widgets" "1.8.250904007"
Copy-Item (Join-Path $widgets "metadata\Microsoft.Windows.Widgets.winmd") $target -Force

Write-Host "Widget-SDK liegt in $target"
