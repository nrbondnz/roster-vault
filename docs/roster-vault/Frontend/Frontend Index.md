# Frontend Index

## App Scaffold (Task 3, in progress)

The Flutter project (`roster_vault`, package `com.rostervault.roster_vault`) now exists at the repo root — `flutter create` targeting Android, iOS, and Windows. `flutter analyze` and `flutter test` are clean.

`lib/main.dart` shows a **device debug screen** — a development-only screen (never the real entry point once the roster screen lands in Task 7) displaying this device's `deviceId` and device public key. `lib/services/device_identity_service.dart` generates and persists both: the device keypair via the `biometric_signature` plugin (hardware-backed ECDSA P-256, Android Keystore/StrongBox or iOS Secure Enclave), the `deviceId` via `flutter_secure_storage`. See [[../Security/Trust Anchors|Trust Anchors]] for the implementation detail and a correctness note about avoiding accidental key rotation.

**Still outstanding:** running this on an actual Android/iOS target to confirm the key is generated once, persists across relaunches, and is genuinely P-256 — a Windows desktop run can't verify the last point, since the plugin falls back to RSA-2048 on Windows. See [[../stories/story-checkpoint-mvp|Story Checkpoint: MVP]] Task 3.

Expected notes once more of the story lands:
- Roster screen (Task 7)
- PIN / biometric prompt flow (Task 6)
- Local verification module (the Dart-side counterpart to [[../Architecture/Offline Sign-In Flow|Offline Sign-In Flow]], Task 5)

## See Also

- [[../Index|Vault Index]]
- [[../Architecture/Architecture Index|Architecture Index]]
