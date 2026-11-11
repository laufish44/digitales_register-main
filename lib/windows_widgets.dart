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

/// Setting up the Windows widgets from inside the app.
///
/// The setup does it when it runs in the open; an update from inside the app
/// runs it silently and skips the one step that needs administrator rights
/// (trusting the widget package's certificate). This does the same as the
/// setup: trust the certificate if needed — Windows asks for administrator
/// rights — and register the package for this user. The widgets themselves
/// are windows/widgets/provider.cpp; their data is the snapshot written in
/// home_widgets.dart.
library;

import 'dart:io';

const _packageName = "LaurinFeichter.DigitalesRegister.Widgets";

String get _appDir => File(Platform.resolvedExecutable).parent.path;
String get _widgetDir => "$_appDir${Platform.pathSeparator}widgets";

/// Whether this installation brings the widget package along.
bool get windowsWidgetsAvailable =>
    Platform.isWindows &&
    File("$_widgetDir${Platform.pathSeparator}DigitalesRegisterWidgets.msix")
        .existsSync();

/// Whether the widgets are set up for this user.
Future<bool> windowsWidgetsInstalled() async {
  if (!Platform.isWindows) return false;
  try {
    final result = await Process.run("powershell.exe", [
      "-NoProfile",
      "-Command",
      "(Get-AppxPackage -Name $_packageName) -ne \$null",
    ]);
    return result.stdout.toString().trim() == "True";
  } catch (_) {
    return false;
  }
}

/// Sets the widgets up. Returns null on success, otherwise what went wrong,
/// in German for the user.
Future<String?> setUpWindowsWidgets() async {
  if (!windowsWidgetsAvailable) {
    return "Diese Installation enthält keine Widgets.";
  }
  final sep = Platform.pathSeparator;
  final cer = "$_widgetDir${sep}DigitalesRegisterWidgets.cer";
  final msix = "$_widgetDir${sep}DigitalesRegisterWidgets.msix";
  String quote(String s) => "'${s.replaceAll("'", "''")}'";
  final script = """
\$ErrorActionPreference = 'Stop'
try {
  \$cer = ${quote(cer)}
  \$c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(\$cer)
  \$store = "Cert:\\LocalMachine\\TrustedPeople\\\$(\$c.Thumbprint)"
  if (-not (Test-Path \$store)) {
    Start-Process certutil.exe -ArgumentList @('-addstore', 'TrustedPeople', "`"\$cer`"") -Verb RunAs -Wait -WindowStyle Hidden
    if (-not (Test-Path \$store)) { Write-Output 'NOTRUST'; exit }
  }
  Add-AppxPackage -Path ${quote(msix)} -ExternalLocation ${quote(_appDir)} -ForceUpdateFromAnyVersion -ForceApplicationShutdown
  Write-Output 'OK'
} catch {
  Write-Output ("ERROR " + \$_.Exception.Message)
}
""";
  try {
    final result = await Process.run("powershell.exe",
        ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script]);
    final out = result.stdout.toString().trim();
    if (out.endsWith("OK")) return null;
    if (out.contains("NOTRUST")) {
      return "Ohne Administratorrechte geht es nicht – Windows muss dem "
          "Zertifikat einmal vertrauen.";
    }
    if (out.contains("WindowsAppRuntime")) {
      return "Es fehlt die Windows App Runtime 1.8 von Microsoft.";
    }
    return "Die Widgets konnten nicht eingerichtet werden"
        "${out.startsWith("ERROR ") ? ": ${out.substring(6)}" : "."}";
  } catch (e) {
    return "Die Widgets konnten nicht eingerichtet werden.";
  }
}
