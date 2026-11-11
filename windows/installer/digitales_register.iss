; Inno Setup script for the Windows installer.
;
; Build the app first, then compile this:
;   flutter build windows --release
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" windows\installer\digitales_register.iss
;
; The result lands in "installation files\Windows\".

#define AppName "Digitales Register"
#define AppVersion "9.1.0"
#define AppPublisher "Laurin Feichter"
#define AppURL "https://github.com/laufish44/digitales_register-main"
#define AppExeName "digitales_register.exe"
; Relative to this script: <repo>/windows/installer -> <repo>
#define RepoDir ".."
#define BuildDir RepoDir + "\..\build\windows\x64\runner\Release"
#define OutputDir RepoDir + "\..\installation files\Windows"
; The widget package (tool/build_widget_package.ps1); optional.
#define WidgetDir RepoDir + "\..\installation files\widgets"
#define ThumbFile WidgetDir + "\thumbprint.txt"
#if FileExists(ThumbFile)
  #define ThumbHandle FileOpen(ThumbFile)
  #define WidgetThumb Trim(FileRead(ThumbHandle))
  #expr FileClose(ThumbHandle)
#else
  #define WidgetThumb ""
#endif

[Setup]
; Keep this GUID stable - Windows recognises updates by it.
AppId={{8F3A6C21-5E47-4B92-9D14-7A2E6B85C3F1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Installs per user by default, so no UAC prompt is needed. Users who want it
; for everyone can still pick that in the first wizard page.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=digitales-register-{#AppVersion}-setup
SetupIconFile={#RepoDir}\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app is 64 bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole build output. The .exe needs the plugin DLLs and the data folder
; next to it, so everything is copied as one unit. Link-time leftovers are
; excluded - they are not part of the application.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.lib,*.exp,*.pdb"
; The Windows widgets: the identity package and its certificate.
Source: "{#WidgetDir}\DigitalesRegisterWidgets.msix"; DestDir: "{app}\widgets"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#WidgetDir}\DigitalesRegisterWidgets.cer"; DestDir: "{app}\widgets"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
; An update from inside the app runs this installer silently (/VERYSILENT,
; see update_service.dart) after the app closed itself; start it again.
Filename: "{app}\{#AppExeName}"; Flags: nowait skipifnotsilent

[Registry]
; The app writes this itself when "Im Hintergrund weiter prüfen" is switched on.
; Declaring it here means uninstalling also removes the autostart entry instead
; of leaving a dead command behind.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "DigitalesRegister"; ValueType: string; ValueData: """{app}\{#AppExeName}"" --background"; Flags: dontcreatekey uninsdeletevalue

[UninstallRun]
; Stop a running background service before removing the files, otherwise the
; still-locked executable is left behind.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExeName}"; Flags: runhidden skipifdoesntexist; RunOnceId: "StopApp"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM dr_widgets.exe"; Flags: runhidden skipifdoesntexist; RunOnceId: "StopWidgets"
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Get-AppxPackage -Name LaurinFeichter.DigitalesRegister.Widgets | Remove-AppxPackage"""; Flags: runhidden skipifdoesntexist; RunOnceId: "RemoveWidgets"

[Code]
// The Windows widgets need the identity package registered for this user,
// and Windows has to trust its (self-made) certificate first. Trusting it
// takes administrator rights once per computer; it is asked for when the
// setup runs in the open. A silent update (from inside the app) never asks:
// it only re-registers when the certificate is trusted already, and the app
// offers "Windows-Widgets einrichten" in its settings otherwise.

const
  WidgetThumbprint = '{#WidgetThumb}';

function WidgetCertificateTrusted: Boolean;
begin
  Result := (WidgetThumbprint <> '') and RegKeyExists(HKLM,
    'SOFTWARE\Microsoft\SystemCertificates\TrustedPeople\Certificates\' + WidgetThumbprint);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  // The widget program may be running; it would keep its file locked.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM dr_widgets.exe', '',
    SW_HIDE, ewWaitUntilTerminated, Code);
  Result := '';
end;

procedure SetUpWidgets;
var
  Code: Integer;
  Msix, Cer: String;
begin
  Msix := ExpandConstant('{app}\widgets\DigitalesRegisterWidgets.msix');
  Cer := ExpandConstant('{app}\widgets\DigitalesRegisterWidgets.cer');
  if not FileExists(Msix) then Exit;
  // Widgets exist from Windows 11 on.
  if GetWindowsVersion < $0A0055F0 then Exit;
  if not WidgetCertificateTrusted then
  begin
    if WizardSilent then Exit;
    if MsgBox('Für die Windows-Widgets (Widgets-Board und Sperrbildschirm) muss Windows dem Zertifikat ' +
      'des Digitalen Registers einmal vertrauen. Dafür fragt Windows gleich nach Administratorrechten.' + #13#10#13#10 +
      'Ohne das läuft die App ganz normal, nur ohne Widgets. Einrichten?',
      mbConfirmation, MB_YESNO) <> IDYES then Exit;
    if not ShellExec('runas', ExpandConstant('{sys}\certutil.exe'),
      '-addstore TrustedPeople "' + Cer + '"', '', SW_HIDE,
      ewWaitUntilTerminated, Code) then Exit;
    if not WidgetCertificateTrusted then Exit;
  end;
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "' +
    'Add-AppxPackage -Path ''' + Msix + ''' -ExternalLocation ''' +
    ExpandConstant('{app}') + ''' -ForceUpdateFromAnyVersion -ForceApplicationShutdown"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then SetUpWidgets;
end;
