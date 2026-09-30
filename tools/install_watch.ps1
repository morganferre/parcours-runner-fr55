# Copies bin\ParcoursRunner.prg to GARMIN\APPS on the watch connected over USB.
# Usage: powershell -ExecutionPolicy Bypass -File tools\install_watch.ps1
# The Forerunner 55 shows up either as a drive (E:, F:...) or as a "Forerunner 55" device (MTP).

$prg = Join-Path (Split-Path $PSScriptRoot -Parent) "bin\ParcoursRunner.prg"
if (-not (Test-Path $prg)) {
    Write-Host "File not found: $prg. Run tools\prepare_route.py first." -ForegroundColor Red
    exit 1
}

# 1) Watch seen as a regular USB drive
foreach ($d in Get-PSDrive -PSProvider FileSystem) {
    $apps = Join-Path $d.Root "GARMIN\APPS"
    if (Test-Path $apps) {
        Copy-Item $prg (Join-Path $apps "ParcoursRunner.prg") -Force
        Write-Host "Copied to $apps. Unplug the watch: the app is ready." -ForegroundColor Green
        exit 0
    }
}

# 2) Watch seen as a media device (MTP)
$shell = New-Object -ComObject Shell.Application
$pc = $shell.NameSpace(17)
$device = $pc.Items() | Where-Object { $_.Name -match "Forerunner|Garmin" } | Select-Object -First 1
if (-not $device) {
    Write-Host "Watch not found. Plug it in over USB, wait until it shows up in File Explorer, then run again." -ForegroundColor Red
    exit 2
}

function Find-Child($folder, $name) {
    return $folder.Items() | Where-Object { $_.Name -eq $name } | Select-Object -First 1
}

$top = $device.GetFolder
$garmin = Find-Child $top "GARMIN"
if (-not $garmin) {
    # Some devices have an "Internal Storage" level before GARMIN
    foreach ($item in $top.Items()) {
        $garmin = Find-Child $item.GetFolder "GARMIN"
        if ($garmin) { break }
    }
}
if (-not $garmin) {
    Write-Host "GARMIN folder not found on $($device.Name)." -ForegroundColor Red
    exit 3
}
$apps = Find-Child $garmin.GetFolder "APPS"
if (-not $apps) {
    Write-Host "GARMIN\APPS folder not found on $($device.Name)." -ForegroundColor Red
    exit 3
}

# 16 = answer "Yes to all" if the file already exists
$apps.GetFolder.CopyHere($prg, 16)
Start-Sleep -Seconds 5
Write-Host "Copied to GARMIN\APPS on $($device.Name). Unplug the watch: the app is ready." -ForegroundColor Green
