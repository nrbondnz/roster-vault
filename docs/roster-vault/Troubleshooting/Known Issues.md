# Known Issues

Operational surprises, third-party bugs, and tooling quirks discovered while running this project for real — captured the moment they're understood, per the [[../../agents/docs-agent/docs-agent|Docs Agent]]'s directive. These are not necessarily code defects in this repo; several are third-party or environment issues that just happen to block work here.

## RESOLVED — `biometric_signature` "Foreground activity required" on real Android hardware (was a missed setup step, not a plugin bug)

**Symptom:** [[../Security/Trust Anchors|Trust Anchor 2]]'s device-keypair generation (`DeviceIdentityService.ensureDeviceIdentity`, via `biometric_signature`) threw `BiometricError.unknown "Foreground activity required"` on a real Samsung Galaxy A06 (Android 16 / API 36), visible on screen as `Device identity failed: Bad state: Device key generation failed: BiometricError.unknown Foreground activity required`.

**Confirmed not a race condition or launch-method artifact.** Reproduced identically 3 times: once via the normal `_AuthGate` → `DeviceDebugScreen` transition after a real Cognito sign-in, once after `adb shell am force-stop` + `monkey -c android.intent.category.LAUNCHER` relaunch, once after `adb shell am force-stop` + `adb shell am start -n <pkg>/.MainActivity` relaunch. `adb logcat` confirmed the app was genuinely foregrounded and drawn well before the failure — `ActivityTaskManager: Fully drawn com.rostervault.roster_vault/.MainActivity` logged roughly 0.8s *before* the plugin's own failure fired.

**Diagnostic dead end, kept for the record:** the failure initially looked like a plugin-internal bug. Reading `~/.pub-cache/hosted/pub.dev/biometric_signature-13.0.0/android/src/main/kotlin/com/visionflutter/biometric_signature/BiometricSignaturePlugin.kt` showed `createKeys()` (~line 107-118) checking its own `ActivityAware`-supplied `activity` field and failing immediately if `null`. That looked like an emerging-compatibility issue: the plugin applies its own Kotlin Gradle Plugin (KGP), which Flutter's own build output flagged as a problem class — *"Future versions of Flutter will fail to build if your app uses plugins that apply KGP."* On that hypothesis, `pubspec.yaml`'s `biometric_signature` dependency was temporarily switched to a `git:` dependency pinned to commit `9cccdd216dbe6e8dc07156ece409997919c41f04`, **"fix(android): support AGP 9 built-in Kotlin and update Gradle DSL"** (landed on the plugin's `main` branch after 13.0.0 was tagged, so not in the pub.dev release). Rebuilt (32.1s — confirmed a genuine recompile, not a cached no-op) and reinstalled on the same real device: **identical failure.** That commit fixes a Gradle/AGP9 *build-configuration* compatibility problem — a different bug that happened to live near the same KGP-related code, not this one. Reverted `pubspec.yaml` back to the hosted `^13.0.0` afterward, since the git pin carried real risk (depending on an arbitrary external commit) for zero benefit. Searched the plugin's GitHub issues for `"Foreground activity required"` and more broadly for `activity` — no existing issue matched.

**Actual root cause, found by reading the plugin's own README instead of just its source:** `BiometricSignaturePlugin.kt` types its Activity reference as `private var activity: FlutterFragmentActivity? = null`, populated in `onAttachedToActivity` via `activity = binding.activity as? FlutterFragmentActivity` — a *safe cast*. This project's `android/app/src/main/kotlin/com/rostervault/roster_vault/MainActivity.kt` extended plain `io.flutter.embedding.android.FlutterActivity` (Flutter's default template), not `FlutterFragmentActivity` — so that cast always silently returned `null`, regardless of the real Activity being attached and drawn. This is the plugin's own documented, required integration step: its `README.md` states verbatim (line 265), *"This plugin requires the use of a `FragmentActivity` instead of `Activity`. Update your `MainActivity.kt` to extend `FlutterFragmentActivity`,"* with a code sample matching exactly what was needed. Task 3's original scaffolding never applied it — this was always a gap in this repo's own setup, not a defect in the plugin.

**Fix:** `MainActivity.kt` changed to `class MainActivity : FlutterFragmentActivity()` (inline comment added referencing this page). Rebuilt and reinstalled on the same real device.

**Result: confirmed working.** Real ECDSA P-256 device key generated successfully — Device ID `fe8888db42d5c63fddb42e91291a0481`, a short SPKI public key starting `MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcD...` (that OID prefix identifies the EC/P-256 curve — a completely different, much shorter shape than the long RSA-2048 SPKI seen on the earlier Windows dev-convenience run, confirming this is genuinely P-256, not another RSA fallback). This also unblocked real end-to-end enrollment on the same device: signing in, tapping "Enroll this device," and getting back a KMS-signed token that verified locally with **Signature: VALID** and full decoded claims (`user_id`, `device_id`, `scopes: [offline_signin]`, `epoch`, `iat`) shown on screen — see Task 4c and Task 3 in the story checkpoint.

**Lesson for next time:** when a plugin's `ActivityAware` binding looks broken, check the plugin's README for a required base-Activity change *before* assuming a build-tooling incompatibility — the second hypothesis was a plausible-looking dead end that cost real effort, while the actual answer was in the setup docs the whole time.

## Wireless ADB pairing fails instantly with "protocol fault"

**Symptom:** `adb pair <ip>:<port> <code>` fails immediately (not a timeout) with `error: protocol fault (couldn't read status message): No error`, on Windows, against a real Android phone's "Wireless debugging → Pair device with pairing code" screen.

**Ruled out:** pairing-code expiry (reproduced with multiple fresh codes, tried immediately after receiving them), Windows Firewall (`Get-NetFirewallRule -DisplayName "*adb*"` showed only inbound-allow rules, and the default outbound policy isn't blocking), subnet mismatch (host and phone were confirmed on the same `192.168.68.0/24` Wi-Fi network via `Get-NetIPAddress`).

**Attempted fix:** regenerated adb's local key pair — killed the adb server, renamed `%USERPROFILE%\.android\adbkey` and `adbkey.pub` out of the way (forcing regeneration on next `adb start-server`), restarted the server. This is a documented fix for this exact error message in other adb-on-Windows reports, but it was **not confirmed to actually fix it** here — the team switched to a USB connection instead of re-testing wireless pairing after the key regeneration, so this remains an open, only-partially-investigated issue rather than a confirmed root cause + fix.

**Workaround used instead:** USB connection. Requires accepting the on-device "Allow USB debugging?" prompt, *and* setting the USB notification's connection mode to "File transfer" rather than the default charging-only mode — without both, `adb devices` never showed the phone as `device` (stayed absent or `unauthorized`) on this Samsung phone. After a phone restart, USB authorization resets and needs to be re-accepted on-device (expected Android behavior, noted here for completeness). Once authorized once over USB, wireless debugging (plain `adb connect`, without a fresh `adb pair`) worked normally afterward on this same phone.

## A real Android phone's touchscreen stopped registering finger input mid-session

**Symptom:** mid-session, the phone stopped responding to any real finger touches — including the physical/on-screen Home button, which should never be blocked by app state on Android.

**Confirmed this was NOT an app freeze or full system hang:** `adb shell input keyevent KEYCODE_HOME` (a synthetic, adb-injected input event) worked instantly and navigated to the home screen, while real finger touches did nothing at all, on the same screen, moments apart. Since synthetic input injection and physical touch delivery go through different paths (`InputManager` injection vs. the touchscreen digitizer), this points at the digitizer/touch layer specifically, not the window manager, the app, or ADB connectivity.

**Resolved by:** restarting the phone. Notably, the phone would not respond to any physical buttons (power/volume) to initiate a restart until the USB cable was physically removed — worth knowing if this recurs, since attempting a forced restart over USB may not work either.

**Root cause:** unconfirmed. Documented as an observed device quirk on this specific phone, not a diagnosed hardware or software fault.

## `adb shell input` automation gotchas when driving a real login form

Discovered live while scripting a sign-in flow via `adb shell input tap`/`input text` (used as a substitute for real user interaction, the same way Win32 input simulation was used to drive the Windows build elsewhere in this project):

1. **The on-screen keyboard shifts the layout.** Tapping a text field and typing into it brings up the IME keyboard, which resizes the visible content area — later fields (e.g. a password field below an email field) move upward to stay above the keyboard. A second tap using coordinates captured *before* the keyboard appeared can land on the wrong, already-shifted field. Always re-screenshot after the keyboard appears and use the post-keyboard coordinates for subsequent taps.
2. **Tapping a field does not put the cursor at the end of its existing text.** `input keyevent KEYCODE_DEL` repeated N times deletes backward from wherever the cursor landed (often mid-string for a tap in the middle of a long value), which can leave a trailing fragment of the old text instead of clearing it fully. Fix: send `input keyevent KEYCODE_MOVE_END` immediately after the tap, *before* the delete loop, to guarantee deletion starts from the true end of the field.

## See Also

- [[Troubleshooting Index]]
- [[../Security/Trust Anchors|Trust Anchors]]
- [[../stories/story-checkpoint-mvp|Story Checkpoint: MVP]]
