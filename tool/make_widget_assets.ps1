# Draws the logos the widget package needs (windows/widgets/package/Assets)
# from the app icon. The results are committed; the previews of the widget
# picker come from tool\render_widget_previews.ps1.

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

# The previews of the widget picker are rendered from the real cards:
# tool\render_widget_previews.ps1.

$icon.Dispose()
Write-Host "Bilder liegen in $out"
