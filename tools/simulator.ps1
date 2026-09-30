# Drives the FR55 simulator: builds, launches, clicks the buttons, takes a screenshot.
# Example: powershell -File tools\simulator.ps1 -Build -Run -Keys "down,start" -Shot test
# Buttons: up, down, start, back. Screenshots (.png) and log (run_log.txt) in %TEMP%\parcours_runner_sim.
# Developer key: -Key path, otherwise the one set in VS Code (monkeyC.developerKeyPath).
param([switch]$Build, [switch]$Run, [string]$Keys = "", [string]$Shot = "", [int]$Wait = 2, [string]$Key = "")
$cfg = Join-Path $env:APPDATA "Garmin\ConnectIQ\current-sdk.cfg"
if (-not (Test-Path $cfg)) { Write-Host "Connect IQ SDK not found. Install it with Garmin's SDK Manager." -ForegroundColor Red; exit 1 }
$sdk = (Get-Content $cfg -Raw).Trim().TrimEnd("\")
$proj = Split-Path $PSScriptRoot -Parent
$scr = Join-Path $env:TEMP "parcours_runner_sim"; New-Item -ItemType Directory -Force $scr | Out-Null
if ($Build) {
    if ($Key -eq "") {
        $vs = Join-Path $env:APPDATA "Code\User\settings.json"
        if ((Test-Path $vs) -and ((Get-Content $vs -Raw -Encoding UTF8) -match '"monkeyC\.developerKeyPath"\s*:\s*"([^"]+)"')) { $Key = $Matches[1].Replace('\\', '\') }
    }
    if ($Key -eq "") { Write-Host "Developer key not found: pass it with -Key path\developer_key" -ForegroundColor Red; exit 1 }
    $out = & "$sdk\bin\monkeyc.bat" -f "$proj\monkey.jungle" -d fr55 -o "$proj\bin\ParcoursRunner.prg" -y $Key 2>&1
    $out | Select-String "ERROR|BUILD" | ForEach-Object { $_.Line }
    if (-not ($out -match "BUILD SUCCESSFUL")) { exit 1 }
    if (-not $Run -and $Keys -eq "" -and $Shot -eq "") { exit 0 }
}
if ($Run) {
    if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) { Start-Process "$sdk\bin\simulator.exe"; Start-Sleep 10 }
    Start-Process -NoNewWindow -FilePath "$sdk\bin\monkeydo.bat" -ArgumentList "`"$proj\bin\ParcoursRunner.prg`" fr55" -RedirectStandardOutput "$scr\run_log.txt"
    Start-Sleep 8
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ("SimW" -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SimW { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e); public struct RECT { public int L,T,R,B; } }
"@
}
$p = Get-Process simulator
$r = New-Object SimW+RECT
[SimW]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$pos = @{ up = @(48, 300); down = @(52, 386); start = @(358, 212); back = @(358, 386) }
if ($Keys -ne "") {
    [SimW]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    $old = [System.Windows.Forms.Cursor]::Position
    foreach ($k in $Keys.Split(",")) {
        $c = $pos[$k.Trim()]
        [SimW]::SetCursorPos($r.L + $c[0], $r.T + $c[1]) | Out-Null
        Start-Sleep -Milliseconds 200
        [SimW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 150; [SimW]::mouse_event(4,0,0,0,0)
        Start-Sleep -Milliseconds 700
    }
    [SimW]::SetCursorPos($old.X, $old.Y) | Out-Null
}
Start-Sleep $Wait
if ($Shot -ne "") {
    $w = $r.R - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $bmp.Save("$scr\$Shot.png")
    "capture $Shot"
}
Get-Content "$scr\run_log.txt" -Tail 5 -ErrorAction SilentlyContinue
