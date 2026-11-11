# Draws the pictures the widget package needs (windows/widgets/package/Assets):
# the logos, from the app icon, and one preview per widget for the
# "Widgets hinzufügen" dialog. Run again after changing a widget's look; the
# results are committed.

Add-Type -AssemblyName System.Drawing
$root = Join-Path $PSScriptRoot ".."
$out = Join-Path $root "windows\widgets\package\Assets"
New-Item -ItemType Directory -Force $out | Out-Null
$icon = [System.Drawing.Image]::FromFile((Join-Path $root "assets\transparent_no_padding.png"))

function Save-Logo($name, $size, $padding) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = "HighQualityBicubic"
    $g.Clear([System.Drawing.Color]::Transparent)
    $inner = $size - 2 * $padding
    $g.DrawImage($icon, $padding, $padding, $inner, $inner)
    $bmp.Save((Join-Path $out $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

Save-Logo "Square44x44Logo.png" 44 2
Save-Logo "Square150x150Logo.png" 150 20
Save-Logo "StoreLogo.png" 50 2
Save-Logo "WidgetIcon.png" 64 4

# Previews: a light card with the lines a widget shows.
function Save-Preview($name, $lines) {
    $w = 300; $h = 304
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    $g.TextRenderingHint = "AntiAliasGridFit"
    $g.Clear([System.Drawing.Color]::FromArgb(243, 246, 250))
    $y = 22
    foreach ($line in $lines) {
        $size, $bold, $color, $text = $line
        $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
        $font = New-Object System.Drawing.Font "Segoe UI", $size, $style, ([System.Drawing.GraphicsUnit]::Pixel)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($color))
        $g.DrawString($text, $font, $brush, 20, $y)
        $y += [int]($size * 1.45)
        $font.Dispose(); $brush.Dispose()
    }
    $g.DrawImage($icon, $w - 52, $h - 52, 32, 32)
    $bmp.Save((Join-Path $out $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

$dark = "#1b1b1f"; $grey = "#5f6368"; $blue = "#1565c0"; $red = "#c62828"; $green = "#2e7d32"
Save-Preview "Preview_lesson.png" @(
    @(30, $true, $dark, "Mathematik"),
    @(24, $false, $blue, "noch 1:12 h (23 Min)"),
    @(17, $false, $grey, "1.–2. Stunde · Raum 12"),
    @(17, $false, $grey, "Danach: Italienisch um 09:40"),
    @(17, $false, $grey, "Schulschluss 13:25"))
Save-Preview "Preview_exams.png" @(
    @(20, $true, $dark, "Prüfungen (3)"),
    @(19, $true, $red, "Fr 13.11.  Schularbeit"),
    @(16, $false, $grey, "              Mathematik"),
    @(19, $true, $red, "Di 17.11.  Test"),
    @(16, $false, $grey, "              Deutsch"),
    @(19, $true, $red, "Mi 18.11.  Prüfung"),
    @(16, $false, $grey, "              Englisch"))
Save-Preview "Preview_day.png" @(
    @(20, $true, $dark, "Morgen · Do 12.11."),
    @(17, $false, $grey, "6 Stunden · 1 Test · 2 Hausaufgaben"),
    @(18, $true, $red, "Test   Deutsch"),
    @(18, $false, $dark, "HA     Italienisch"),
    @(18, $false, $dark, "1.      Mathematik 07:45"),
    @(18, $false, $dark, "2.      Englisch 08:35"))
Save-Preview "Preview_countdown.png" @(
    @(20, $true, $grey, "Weihnachtsferien"),
    @(56, $true, $blue, "43 Tage"),
    @(17, $false, $grey, "ab Do 24.12."),
    @(17, $false, $grey, "Schulende in 217 Tagen"))
Save-Preview "Preview_grades.png" @(
    @(20, $true, $grey, "Gesamtschnitt"),
    @(56, $true, $blue, "8,61"),
    @(17, $false, $grey, "Trend +0,25 pro Monat"))
Save-Preview "Preview_absences.png" @(
    @(20, $true, $grey, "Absenzen"),
    @(56, $true, $green, "7,6 %"),
    @(17, $false, $grey, "Grenze 25 %"),
    @(17, $false, $grey, "Noch 120 Stunden Luft"))

$icon.Dispose()
Write-Host "Bilder liegen in $out"
