# Renders the preview pictures of the widget picker
# (windows/widgets/package/Assets/Preview_*.png) from the real cards: the
# widget program draws every widget from a snapshot (dr_widgets.exe --dump),
# and headless Chrome renders them with the Adaptive Cards renderer.
#
#   tool\render_widget_previews.ps1 -Snapshot <demo-widgets.json> [-At 2026-11-13T09:10]
#
# Use a snapshot with made-up grades and absences: the pictures are public.
# Needs a Windows build (build\windows\x64\runner\Release), Chrome and the
# internet (the renderer comes from unpkg.com).

param(
    [Parameter(Mandatory = $true)][string]$Snapshot,
    [string]$At = ""
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$exe = Join-Path $root "build\windows\x64\runner\Release\dr_widgets.exe"
$assets = Join-Path $root "windows\widgets\package\Assets"
$chrome = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "dr-widget-previews"
New-Item -ItemType Directory -Force $temp | Out-Null

$cards = Join-Path $temp "cards.json"
$env:DR_WIDGETS_SNAPSHOT = (Resolve-Path $Snapshot).Path
$arguments = @("--dump", "`"$cards`"")
if ($At) { $arguments += $At }
(Start-Process $exe -ArgumentList $arguments -PassThru).WaitForExit(30000) | Out-Null
Remove-Item Env:DR_WIDGETS_SNAPSHOT
$all = Get-Content $cards -Raw | ConvertFrom-Json

foreach ($widget in "lesson", "exams", "day", "countdown", "grades", "absences") {
    $card = $all."${widget}_medium" | ConvertTo-Json -Depth 30 -Compress
    $html = @"
<!doctype html><html><head><meta charset="utf-8">
<script src="https://unpkg.com/adaptivecards@3.0.4/dist/adaptivecards.min.js"></script>
<style>html,body{margin:0;background:#2b2b2b;font-family:'Segoe UI';overflow:hidden}
#c{box-sizing:border-box;width:340px;height:190px;padding:22px 18px;color:#fff}</style>
</head><body><div id="c"></div><script>
const host = new AdaptiveCards.HostConfig({ fontFamily: "Segoe UI",
  fontSizes: { small: 13, default: 15, medium: 18, large: 24, extraLarge: 30 },
  containerStyles: { default: { backgroundColor: "#00000000",
    foregroundColors: { default: { default: "#ffffff", subtle: "#c8c8c8" },
      accent: { default: "#6cb6ff", subtle: "#6cb6ff" }, attention: { default: "#ff7b72", subtle: "#ff7b72" },
      good: { default: "#56d364", subtle: "#56d364" }, warning: { default: "#e3b341", subtle: "#e3b341" } } } } });
const ac = new AdaptiveCards.AdaptiveCard(); ac.hostConfig = host; ac.parse($card);
document.getElementById("c").appendChild(ac.render());
</script></body></html>
"@
    $page = Join-Path $temp "$widget.html"
    Set-Content $page $html -Encoding UTF8
    $out = Join-Path $assets "Preview_$widget.png"
    $p = Start-Process $chrome -ArgumentList @("--headless=new", "--disable-gpu",
        "--hide-scrollbars", "--user-data-dir=`"$temp\chrome`"", "--window-size=340,190",
        "--virtual-time-budget=6000", "--screenshot=`"$out`"",
        "`"file:///$($page -replace '\\','/')`"") -PassThru -WindowStyle Hidden
    $p.WaitForExit(60000) | Out-Null
    Write-Host "Preview_$widget.png"
}
