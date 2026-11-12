<#
.SYNOPSIS
    Samples the repro app's memory after every round.

.DESCRIPTION
    Launches the app in profile mode (Impeller or Skia), watches logcat for the
    "IMPELLER_REPRO round=N" marker the app prints after each round, and takes
    `dumpsys meminfo` at that moment. Writes one CSV per run under results/.

.PARAMETER Flutter
    Flutter executable to use. Defaults to `flutter` on PATH. Pass another SDK
    (for example C:\sdk\flutter-3.50\bin\flutter.bat, or `fvm` with
    -FlutterArgs 'flutter') to compare versions.

.EXAMPLE
    ./tool/measure.ps1 -Renderer impeller -Scenario images -Rounds 30
    ./tool/measure.ps1 -Renderer skia     -Scenario images -Rounds 30
    ./tool/measure.ps1 -Renderer impeller -Flutter C:\sdk\flutter-3.50\bin\flutter.bat
#>
param(
    [ValidateSet('impeller', 'skia')]
    [string]$Renderer = 'impeller',
    [ValidateSet('images', 'stack', 'no_images', 'fresh')]
    [string]$Scenario = 'images',
    [int]$Rounds = 30,
    [int]$PauseMs = 4000,
    [string]$Device,
    [string]$Flutter = 'flutter',
    [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'
$package = 'dev.ccisne.impeller_gles_memory'
$root = Split-Path $PSScriptRoot -Parent
$adbPrefix = if ($Device) { @('-s', $Device) } else { @() }
function Adb { & adb @adbPrefix @args }

# Device and toolchain info, recorded next to the CSV.
$model = (Adb shell getprop ro.product.model).Trim()
$android = (Adb shell getprop ro.build.version.release).Trim()
$gpu = ((Adb shell dumpsys SurfaceFlinger) | Select-String 'GLES:' | Select-Object -First 1).ToString().Trim()
$flutterVersion = (& $Flutter @FlutterArgs --version 2>&1 | Select-Object -First 1).ToString().Trim()
Write-Host "Device: $model, Android $android"
Write-Host "GPU: $gpu"
Write-Host "Flutter: $flutterVersion"

New-Item -ItemType Directory -Force (Join-Path $root 'results') | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csv = Join-Path $root "results/$stamp-$Renderer-$Scenario.csv"
@(
    "# device=$model android=$android",
    "# $gpu",
    "# $flutterVersion",
    'round,time,total_pss_kb,graphics_kb,gl_mtrack_kb,egl_mtrack_kb,native_heap_kb'
) | Set-Content $csv

# `--no-enable-impeller` only applies to debug and profile builds, which is
# enough for measuring. The app starts its rounds by itself.
$runArgs = $FlutterArgs + @('run', '--profile', "--dart-define=SCENARIO=$Scenario",
    "--dart-define=ROUNDS=$Rounds", "--dart-define=PAUSE_MS=$PauseMs")
if ($Renderer -eq 'skia') { $runArgs += '--no-enable-impeller' }
if ($Device) { $runArgs += @('-d', $Device) }
Adb logcat -c
$run = Start-Process $Flutter -ArgumentList $runArgs -WorkingDirectory $root -PassThru -NoNewWindow

function Sample([int]$round) {
    $m = Adb shell dumpsys meminfo $package
    function Value([string]$label) {
        $line = $m | Select-String -Pattern "^\s*$([regex]::Escape($label))\s*:?\s+(\d+)" | Select-Object -First 1
        if ($line) { $line.Matches[0].Groups[1].Value } else { '' }
    }
    $row = @(
        $round, (Get-Date -Format 'HH:mm:ss'),
        (Value 'TOTAL PSS'), (Value 'Graphics'), (Value 'GL mtrack'),
        (Value 'EGL mtrack'), (Value 'Native Heap')
    ) -join ','
    Add-Content $csv $row
    Write-Host "round $round -> $row"
}

try {
    Adb logcat -v brief 'flutter:I' '*:S' | ForEach-Object {
        if ($_ -match 'IMPELLER_REPRO round=(\d+)') { Sample ([int]$Matches[1]) }
        if ($_ -match 'IMPELLER_REPRO end') { throw 'end' }
    }
} catch {
    if ($_.Exception.Message -ne 'end') { throw }
} finally {
    if (-not $run.HasExited) { Stop-Process -Id $run.Id -Force }
    Adb shell am force-stop $package | Out-Null
}
Write-Host "CSV: $csv"
