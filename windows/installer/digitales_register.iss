; Inno Setup script for the Windows installer.
;
; Build the app first, then compile this:
;   flutter build windows --release
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" windows\installer\digitales_register.iss
;
; The result lands in "installation files\Windows\".

#define AppName "Digitales Register"
#define AppVersion "8.3.0"
#define AppPublisher "Michael Debertol"
#define AppURL "https://github.com/miDeb/digitales_register"
#define AppExeName "digitales_register.exe"
; Relative to this script: <repo>/windows/installer -> <repo>
#define RepoDir ".."
#define BuildDir RepoDir + "\..\build\windows\x64\runner\Release"
#define OutputDir RepoDir + "\..\installation files\Windows"

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

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
; The app writes this itself when "Im Hintergrund weiter prüfen" is switched on.
; Declaring it here means uninstalling also removes the autostart entry instead
; of leaving a dead command behind.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "DigitalesRegister"; ValueType: string; ValueData: """{app}\{#AppExeName}"" --background"; Flags: dontcreatekey uninsdeletevalue

[UninstallRun]
; Stop a running background service before removing the files, otherwise the
; still-locked executable is left behind.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExeName}"; Flags: runhidden skipifdoesntexist; RunOnceId: "StopApp"
