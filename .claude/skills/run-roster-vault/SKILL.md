---
name: run-roster-vault
description: Build, launch, screenshot, and hot-reload the Roster Vault Flutter Windows desktop app. Use when asked to run, start, launch, or screenshot the app, or to confirm a change works (e.g. "run the app on Windows", "does hot reload work", "take a screenshot of the app").
---

# Run: Roster Vault (Flutter Windows desktop)

Roster Vault is a Flutter app; the only platform actually built out here
is Windows desktop (`windows/` runner). It's driven by
`driver.ps1` in this skill directory — a PowerShell script that launches
`flutter run -d windows` with redirected stdio (so it can send hot-reload
keystrokes programmatically), resolves the *separate* `roster_vault.exe`
window process Flutter spawns, and captures a real screenshot of that
window via Win32 `PrintWindow`. All paths below are relative to the repo
root (`C:\dev\flutter_projs\appmanagement`).

## Prerequisites

- Flutter SDK on PATH at `C:\dev\flutter` (verified: `flutter --version` →
  Flutter 3.44.8, Dart 3.12.2).
- Visual Studio 2022 with the Desktop C++ workload (required for the
  Windows runner's CMake build — already present in this environment; see
  `flutter doctor -v`, "Visual Studio" check).
- No `apt-get`/Linux setup applies — this is a native Windows build, not
  a container.

## Build

```powershell
pwsh -File .claude\skills\run-roster-vault\driver.ps1 -Action build
```

Runs `flutter build windows --debug` and reports the exit code. Verified
output: `Built build\windows\x64\runner\Debug\roster_vault.exe`
(~10-15s incremental).

## Run (agent path) — use this

```powershell
pwsh -File .claude\skills\run-roster-vault\driver.ps1 -Action smoke
```

This is the primary way to prove the app actually works, not just that
it compiles. It:

1. Launches `flutter run -d windows` (first build ~10-60s; the script
   waits up to 180s for the "Flutter run key commands." ready line).
2. Resolves the actual GUI window: `flutter run`'s own process is the
   *tool* host, not the window — the window belongs to a separately
   spawned `roster_vault.exe` child process, found via
   `Get-Process -Name roster_vault`.
3. Edits `lib/main.dart` live (appends `TEST` to the AppBar title —
   look for the `Device Debug'` needle in the script if that text has
   since changed), sends `r` on the process's stdin to trigger a real
   hot reload, and greps the log for Flutter's own
   `Reloaded N of M libraries in Xms` confirmation.
4. Screenshots the actual window (Win32 `PrintWindow`, `PW_RENDERFULLCONTENT`)
   to `.artifacts/<timestamp>/app_screenshot.png` — **open this and look
   at it**; don't just check the file exists.
5. Reverts the `main.dart` edit and sends `q` to quit cleanly (`finally`
   block, so this happens even if the screenshot step throws).

Verified run output:
```
Hot reload result: Reloaded 1 of 1168 libraries in 387ms
Window handle=1509378 rect=1280x720
PrintWindow returned: True
Verified on disk: ...\app_screenshot.png (33605 bytes)
```
And the screenshot itself visibly shows `Roster Vault — Device Debug TEST`
in the title bar plus a real generated device ID / public key — proof the
edit reached the running app.

For a screenshot only, no source edit:

```powershell
pwsh -File .claude\skills\run-roster-vault\driver.ps1 -Action screenshot
```

Artifacts (log + screenshot) land in
`.claude\skills\run-roster-vault\.artifacts\<timestamp>\` — gitignored,
safe to leave around or delete.

## Run (human path)

```powershell
flutter run -d windows
```

Opens an interactive terminal session with `r`/`R`/`q` key commands and
a real window. Fine at a keyboard; useless for an agent since there's no
way to send it keystrokes or inspect its window without the driver above.

## Gotchas

- **`flutter` from the Bash tool (git-bash) fails** with `Error: Unable
  to find git in your PATH` — `flutter.bat` internally shells out to the
  Windows `where` command, which isn't on git-bash's PATH. Always drive
  Flutter through the PowerShell tool here, not Bash.
- **The window's PID is not `flutter run`'s PID.** `flutter run -d
  windows` stays alive as a Dart tool process (frontend_server + the
  daemon protocol); it spawns `build\windows\x64\runner\Debug\roster_vault.exe`
  as a *child* process, and that's what owns the actual HWND. Screenshotting
  by the wrong PID silently finds no window (see Troubleshooting).
- **`$env:TEMP` isn't a reliable place to write files you'll read back.**
  Writes made by one PowerShell tool invocation to `$env:TEMP` were
  invisible to a later Read/Bash check in this environment (sandboxing).
  Writes inside the repo tree persisted correctly across every
  invocation — that's why artifacts default under `.claude/skills/...`
  instead of the OS temp dir.
- **A PowerShell function that both `Write-Output`s diagnostics and
  `return`s a bool is a trap.** Every `Write-Output` inside the function
  joins the pipeline, so `$ok = Save-WindowScreenshot ...` captures an
  *array* of `(diagnostic strings..., $true_or_false)` — and a non-empty
  PowerShell array is always truthy in `if ($ok)`, regardless of the
  real result. Fixed by using `Write-Host` for in-function diagnostics
  (bypasses the pipeline) and keeping only the final `return` as actual
  output. If you extend the driver with more helper functions, keep
  this in mind.
- **IntelliJ's Flutter plugin can fail to start its own daemon** on
  project open with `Timeout when calling flutter config --machine` if
  IDE indexing/scanning is saturating CPU/disk at that exact moment —
  unrelated to this driver, but if `flutter doctor` is clean and the
  IDE still shows no devices, that's the likely cause. Re-browsing to
  the same SDK path in Settings → Languages & Frameworks → Flutter
  after indexing settles forces a retry that (verified) succeeds in
  under 5s once the system isn't under load.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Cannot overwrite variable pid because it is read-only or constant` | `$pid` is a PowerShell automatic variable (current process ID) — never name a parameter or local variable `$pid`. Driver uses `$targetPid`. |
| Screenshot step reports success but the PNG file doesn't exist | Almost certainly the `$env:TEMP` / pipeline-capture gotchas above. Check `OutDir` is inside the repo, and that diagnostic `Write-Host` lines (not `Write-Output`) actually appear in the console output. |
| `WARN: could not find a visible top-level window for PID <N>` | `<N>` is `flutter run`'s own tool PID, not the app window's PID. Confirm the driver is resolving `Get-Process -Name roster_vault` for the window lookup, not `$proc.Id`. |
| App/dart processes accumulate across repeated manual test runs | The driver's `finally` block sends `q` then force-kills after 3s if still alive, which cleans up both the tool process and its `roster_vault.exe` child. If you `Ctrl+C` a driver invocation mid-run instead of letting it finish, do a manual sweep: `Get-Process roster_vault, dart | Stop-Process -Force` (careful — this also matches the IDE's own long-lived `dart_format`/Flutter-daemon processes if they happen to be named identically; check `Get-CimInstance Win32_Process` command lines before killing if unsure). |
