<#
.SYNOPSIS
  Drives the Roster Vault Flutter Windows desktop app for an agent:
  builds+launches it, optionally makes a live source edit and hot
  reloads, captures a screenshot of the actual app window, then quits.

.PARAMETER Action
  smoke      (default) Launch, hot-reload a trivial visible change in
             lib/main.dart, screenshot, revert the edit, quit. Proves
             build + launch + hot reload + UI all work.
  screenshot Launch, wait for ready, screenshot, quit. No source edit.
  build      Just `flutter build windows` (release-ish check that the
             app compiles), no launch.

.PARAMETER ProjectDir
  Defaults to the repo root two levels above this skill directory
  (<repo>/.claude/skills/run-roster-vault/driver.ps1 -> <repo>).

.PARAMETER OutDir
  Where the log file and screenshot get written. Defaults to a temp
  directory under $env:TEMP so nothing lands in the repo.

.EXAMPLE
  pwsh -File .claude/skills/run-roster-vault/driver.ps1 -Action smoke
#>
param(
    [ValidateSet("smoke", "screenshot", "build")]
    [string]$Action = "smoke",
    [string]$ProjectDir,
    [string]$OutDir
)

$ErrorActionPreference = "Stop"

if (-not $ProjectDir) {
    $ProjectDir = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
}
if (-not $OutDir) {
    # NOTE: $env:TEMP is not reliable here -- writes made by a sandboxed
    # tool invocation to the OS temp dir can be invisible to the next
    # invocation (including the one reading this file back). Artifacts
    # dir lives inside the repo, which has proven consistently readable.
    $OutDir = Join-Path $ProjectDir ".claude\skills\run-roster-vault\.artifacts\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$mainDart = Join-Path $ProjectDir "lib\main.dart"
$logFile = Join-Path $OutDir "flutter_run.log"
$screenshotFile = Join-Path $OutDir "app_screenshot.png"
$flutterBat = "C:\dev\flutter\bin\flutter.bat"

Write-Output "ProjectDir: $ProjectDir"
Write-Output "OutDir:     $OutDir"

if ($Action -eq "build") {
    Write-Output "Running: flutter build windows --debug"
    & $flutterBat build windows --debug
    Write-Output "Exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
}

# ---- Win32 interop for a real screenshot of the app window ----
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class WinCap {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static IntPtr FindWindowForPid(int pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            uint wPid;
            GetWindowThreadProcessId(hWnd, out wPid);
            if (wPid == (uint)pid && IsWindowVisible(hWnd)) {
                RECT r;
                GetWindowRect(hWnd, out r);
                if (r.Right - r.Left > 50 && r.Bottom - r.Top > 50) {
                    found = hWnd;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@ -ReferencedAssemblies System.Drawing -ErrorAction SilentlyContinue

function Save-WindowScreenshot([int]$targetPid, [string]$path) {
    Add-Type -AssemblyName System.Drawing
    $hwnd = [WinCap]::FindWindowForPid($targetPid)
    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Host "WARN: could not find a visible top-level window for PID $targetPid"
        return $false
    }
    $rect = New-Object WinCap+RECT
    [WinCap]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    Write-Host "Window handle=$hwnd rect=${width}x${height}"
    try {
        $bmp = New-Object System.Drawing.Bitmap $width, $height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc()
        $printed = [WinCap]::PrintWindow($hwnd, $hdc, 2)  # PW_RENDERFULLCONTENT
        $g.ReleaseHdc($hdc)
        Write-Host "PrintWindow returned: $printed"
        $dir = Split-Path -Parent $path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose()
        $bmp.Dispose()
    } catch {
        Write-Host "Screenshot EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
        return $false
    }
    Start-Sleep -Milliseconds 200
    if (Test-Path $path) {
        $sz = (Get-Item $path).Length
        Write-Host "Verified on disk: $path ($sz bytes)"
        return $true
    } else {
        Write-Host "Save() returned without error but file is not on disk at $path"
        return $false
    }
}
# ---- end Win32 interop ----

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $flutterBat
$psi.Arguments = "run -d windows"
$psi.WorkingDirectory = $ProjectDir
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$global:hrLogFile = $logFile
$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$outHandler = {
    if ($EventArgs.Data -ne $null) {
        Add-Content -Path $global:hrLogFile -Value $EventArgs.Data
    }
}
Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outHandler | Out-Null
Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $outHandler | Out-Null
$proc.Start() | Out-Null
$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()
Write-Output "Launched flutter run (PID $($proc.Id))"

function Wait-ForMarker($marker, $timeoutSec) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains($marker)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Quit-Flutter {
    try { $proc.StandardInput.WriteLine("q") } catch {}
    Start-Sleep -Seconds 3
    if (-not $proc.HasExited) { $proc.Kill() }
}

Write-Output "Waiting for build + launch (up to 180s)..."
if (-not (Wait-ForMarker "Flutter run key commands." 180)) {
    Write-Output "FAILED: app did not reach ready state within timeout."
    Get-Content $logFile -Tail 60
    Quit-Flutter
    exit 1
}
Write-Output "App is running."

# `flutter run`'s own process (PID above) is the tool/frontend_server host --
# the actual GUI window belongs to the separately-spawned runner exe.
Start-Sleep -Seconds 2
$appProc = Get-Process -Name "roster_vault" -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
if (-not $appProc) {
    Write-Output "WARN: could not find roster_vault.exe process; falling back to flutter tool PID for screenshot (will likely fail to find a window)."
    $appPid = $proc.Id
} else {
    $appPid = $appProc.Id
    Write-Output "App window process: roster_vault.exe (PID $appPid)"
}

# Give the native window a moment to paint before we screenshot / edit.
Start-Sleep -Seconds 1

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$original = $null
try {
    if ($Action -eq "smoke") {
        $original = Get-Content $mainDart -Raw -Encoding UTF8
        $needle = "Device Debug'"
        $replacement = "Device Debug TEST'"
        if (-not $original.Contains($needle)) {
            Write-Output "FAILED: expected text '$needle' not found in lib/main.dart -- edit this script's needle/replacement for your current source."
            exit 1
        }
        $marker = (Get-Content $logFile -Raw).Length
        [System.IO.File]::WriteAllText($mainDart, $original.Replace($needle, $replacement), $utf8NoBom)
        Write-Output "Edited lib/main.dart, triggering hot reload..."
        Start-Sleep -Seconds 2
        $proc.StandardInput.WriteLine("r")

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $reloadResult = $null
        while ($sw.Elapsed.TotalSeconds -lt 40) {
            $newContent = (Get-Content $logFile -Raw).Substring($marker)
            if ($newContent -match "Reloaded \d+ .*librar.*in \d+ms") { $reloadResult = $Matches[0]; break }
            if ($newContent -match "Hot reload was rejected|Try again after fixing|Error") { $reloadResult = "FAILED: $($newContent)"; break }
            Start-Sleep -Milliseconds 500
        }
        Write-Output "Hot reload result: $reloadResult"
        Start-Sleep -Seconds 1
    }

    Write-Output "Capturing screenshot to $screenshotFile ..."
    $ok = Save-WindowScreenshot -targetPid $appPid -path $screenshotFile
    if ($ok) { Write-Output "Screenshot saved: $screenshotFile" } else { Write-Output "Screenshot FAILED" }
}
finally {
    if ($original) {
        [System.IO.File]::WriteAllText($mainDart, $original, $utf8NoBom)
        Write-Output "Reverted lib/main.dart"
    }
    Quit-Flutter
}
Write-Output "DONE"
