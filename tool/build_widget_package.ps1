# Builds the signed identity package for the Windows widgets
# (windows/widgets/package) into "installation files\widgets":
#   DigitalesRegisterWidgets.msix  - registered by the setup next to the app
#   DigitalesRegisterWidgets.cer   - the certificate the setup trusts once
#
# The signing key is made on the first run and kept OUTSIDE the repository, in
# %USERPROFILE%\.digitales_register\widgets-signing.pfx — like the Android
# debug keystore it must never get lost: a package signed with a new key needs
# every user to trust a new certificate (one more admin prompt).

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$subject = "CN=Laurin Feichter (Digitales Register)"
$keyDir = Join-Path $env:USERPROFILE ".digitales_register"
$pfx = Join-Path $keyDir "widgets-signing.pfx"
$password = "digitales-register-widgets"
$out = Join-Path $root "installation files\widgets"
New-Item -ItemType Directory -Force $keyDir, $out | Out-Null

$kit = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "x64\makeappx.exe") } |
    Sort-Object Name | Select-Object -Last 1
if (-not $kit) { throw "Windows SDK (makeappx.exe) nicht gefunden" }
$makeappx = Join-Path $kit.FullName "x64\makeappx.exe"
$signtool = Join-Path $kit.FullName "x64\signtool.exe"

if (-not (Test-Path $pfx)) {
    Write-Host "Erzeuge den Signierschlüssel $pfx"
    $cert = New-SelfSignedCertificate -Type Custom -Subject $subject `
        -KeyUsage DigitalSignature -FriendlyName "Digitales Register Widgets" `
        -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(20) `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null
    Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)"
}
$loaded = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfx, $password)
[System.IO.File]::WriteAllBytes((Join-Path $out "DigitalesRegisterWidgets.cer"), $loaded.Export("Cert"))
Set-Content (Join-Path $out "thumbprint.txt") $loaded.Thumbprint -NoNewline

# The package version follows the app's (9.1.0+64 -> 9.1.0.0).
$version = (Select-String -Path (Join-Path $root "pubspec.yaml") -Pattern "^version:\s*([0-9.]+)").Matches[0].Groups[1].Value
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "dr-widget-package"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $root "windows\widgets\package") $stage -Recurse
New-Item -ItemType Directory -Force (Join-Path $stage "Public") | Out-Null
Set-Content (Join-Path $stage "Public\readme.txt") "Digitales Register Widgets"
$manifest = Join-Path $stage "AppxManifest.xml"
(Get-Content $manifest -Raw) -replace 'Version="0\.0\.0\.0"', "Version=""$version.0""" |
    Set-Content $manifest -Encoding UTF8

$msix = Join-Path $out "DigitalesRegisterWidgets.msix"
# /nv: the program files are outside the package, so there is nothing to check.
& $makeappx pack /d $stage /p $msix /nv /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw "makeappx ist fehlgeschlagen" }
& $signtool sign /fd SHA256 /f $pfx /p $password $msix | Out-Null
if ($LASTEXITCODE -ne 0) { throw "signtool ist fehlgeschlagen" }
Write-Host "Widget-Paket ${version}: $msix"
