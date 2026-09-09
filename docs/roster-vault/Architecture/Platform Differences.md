# Platform Differences

Windows, Android, and iOS diverge in exactly three places: how the hardware-backed device key ([[../Security/Trust Anchors|Trust Anchor 2]]) actually gets created, what format its signatures come back in, and what "delete the app" actually clears. Everything else — the KMS issuer key, the AppSync/Lambda enrollment path, [[Offline Sign-In Flow]], the PIN-wraps-token design in [[Multi-User Partitioning]] — is platform-agnostic and unchanged. This page exists so those three differences live in one place instead of being scattered across [[../Security/Trust Anchors|Trust Anchors]] and [[../Troubleshooting/Known Issues|Known Issues]], which remain the sourced, detailed versions this page organizes and links out to rather than duplicates.

**Read the verification-status column carefully.** "Verified" means observed on real hardware this session. "Reasoned from source" means the plugin's actual Swift/Kotlin implementation was read directly and the conclusion follows from that reading — a stronger basis than a guess, but explicitly *not* the same bar this project has held everywhere else, which is proof on the device, not proof by inspection. The Android row went through both stages: it looked fine on inspection once, and was still wrong (see [[../Troubleshooting/Known Issues|Known Issues]]'s `FlutterFragmentActivity` entry) until it was actually run. Nothing on the iOS row has cleared that bar yet, because no Mac has been available in this environment to run it on.

## Device Key Generation

| | Windows | Android | iOS |
|---|---|---|---|
| **Algorithm actually produced** | RSA-2048 (plugin ignores the requested `SignatureType.ecdsa` outright — its own documented behavior) | ECDSA P-256, hardware-backed (Android Keystore) | ECDSA P-256, hardware-backed (Secure Enclave) — reasoned from source, not yet verified |
| **What gates key creation** | Nothing device-specific; a dev-convenience fallback, not a deployment target | Required `MainActivity.kt` to extend `FlutterFragmentActivity` instead of Flutter's template-default `FlutterActivity` — a real bug, found and fixed this session | With `requireAuthentication: false` (this project's actual setting), the plugin's source shows it deliberately omits any passcode/biometry access-control flag — should not require a device passcode to be set at all |
| **Verification status** | N/A — not a deployment target | **Verified**, 2026-09-10, Samsung Galaxy A06 (Android 16 / API 36) | **Reasoned from source** (`BiometricSignaturePlugin.swift`, read directly) — not yet run |

The Android row is the cautionary tale for the iOS row: the plugin's Kotlin source *also* looked fine on a first read (an `ActivityAware`-supplied `activity` field, checked before use) — the actual bug was a missing setup step documented only in the plugin's README, not visible from the source alone. Full diagnosis: [[../Troubleshooting/Known Issues|Known Issues]]. Implemented in `lib/services/device_identity_service.dart`; the required Android fix is `android/app/src/main/kotlin/com/rostervault/roster_vault/MainActivity.kt`.

## Signature Format

Both platforms that actually produce ECDSA P-256 encode the signature the same way — DER (ASN.1 `SEQUENCE{INTEGER r, INTEGER s}`):

| | Android | iOS |
|---|---|---|
| **API called** | `java.security.Signature.getInstance("SHA256withECDSA")` — standard JCA, always DER | `SecKeyCreateSignature(_, .ecdsaSignatureMessageX962SHA256, _)` — X9.62, which is also DER |
| **Consequence** | `UserIdentityService`'s DER-to-raw conversion (mirroring the same fix already needed for KMS's own DER output in `amplify/functions/enroll/handler.ts`) is not Android-specific code — it should be the correct conversion on iOS too, unchanged | Same conversion, not yet exercised against a real iOS-produced signature |
| **Verification status** | **Verified** — real device-to-token round trip, real hardware | **Reasoned from source** — the API contract implies DER, not observed |

If this turns out wrong on real iOS hardware, it will fail loudly (a signature verification failure), not silently — `UserIdentityService.signChallenge` and `TokenVerifier` both either produce a byte-correct raw signature or don't, there's no partial-success case.

## Local Storage Persistence on Uninstall

The one difference with an actual behavioral consequence beyond "which crypto backend":

| | Android | iOS |
|---|---|---|
| **What "delete the app" clears** | Everything — `flutter_secure_storage` (Keychain-equivalent) and any [[Multi-User Partitioning\|EncryptedPartitionStore]] files are app-scoped and wiped by the OS on uninstall | **Nothing.** iOS Keychain items survive app deletion by design (Apple's own documented behavior, meant for e.g. banking apps that shouldn't lose credentials on reinstall) |
| **Why this matters here specifically** | Matches the project's implicit assumption throughout | This project's entire premise is a shared, unmanaged device with no MDM ([[../Management/The Actual Requirement|The Actual Requirement]]) — without a fix, deleting and reinstalling Roster Vault on an iPhone would silently keep the old `K_device`, every enrolled token, and every PIN-wrapped partition key from before the reinstall |
| **Fix** | None needed | `lib/services/fresh_install_guard.dart` (`FreshInstallGuard`) — called first in `main()`, before anything else touches secure storage. Detects a fresh install via a marker file in the app support directory (which *is* removed on iOS uninstall, unlike Keychain) and wipes stale secure-storage entries and partition files when the marker is absent but old data is present |
| **Verification status** | N/A — no fix needed | **Unit-tested** (`test/fresh_install_guard_test.dart`, 4 cases, real temp directory + in-memory storage fake), **not yet verified against the real Keychain or a real install/delete/reinstall cycle** |

Full writeup, including why the fix design (a marker file, not a version check or a "have I run before" flag) was chosen: [[../Troubleshooting/Known Issues|Known Issues]].

## What's Genuinely Unchanged

Worth stating explicitly so the differences above don't read as bigger than they are — everything downstream of key generation is identical code, no platform branches:
- [[Enrollment Flow]] — the same `enroll` mutation call, same Lambda, same KMS signing, regardless of which platform's key made the request.
- [[Offline Sign-In Flow]] — `OfflineVerifier`'s signature/expiry/device-id/epoch/challenge-response chain is pure Dart, no platform import at all.
- [[Multi-User Partitioning]]'s PIN-wraps-token design — `PinService`, `PartitionKeyService`, `DeviceMasterKeyService` are all pure Dart (`package:cryptography`), and `EncryptedPartitionStore`'s `sqlite3mc` cipher build is selected via the same `pubspec.yaml` hook on every platform. Not independently confirmed that the `sqlite3mc` precompiled binary ships for iOS the same way it does for Android/Windows — the hook documentation implies yes ("all platforms supported by Dart") but this wasn't checked directly.

## Not Yet Looked At

- `local_auth` — declared in [[../Backend/Tech Stack Mapping|Tech Stack Mapping]] for biometric unlock, but not wired into `LocalUnlockService` or any other service yet, on any platform. No platform-difference analysis exists because there's no implementation yet to analyze.
- Whether the `sqlite3mc` build genuinely ships for iOS (see above).

## See Also

- [[Architecture Index]]
- [[../Security/Trust Anchors|Trust Anchors]] — Anchor 2's own iOS bullet, the primary source for the device-key findings above
- [[../Troubleshooting/Known Issues|Known Issues]] — full diagnosis of both the Android `FlutterFragmentActivity` bug and the iOS Keychain-persistence fix
- [[../stories/story-checkpoint-mvp|Story Checkpoint: MVP]] — "Post-Story: iOS Readiness Scoping" for the narrative of how this was found
