# Frontend Index

## App Scaffold (Task 3, in progress)

The Flutter project (`roster_vault`, package `com.rostervault.roster_vault`) now exists at the repo root — `flutter create` targeting Android, iOS, and Windows. `flutter analyze` and `flutter test` are clean.

`lib/main.dart` currently shows a **device debug screen** — a development-only screen (never the real entry point once the roster screen lands in Task 7) that will display this device's `deviceId` and device public key once the device keypair generation work is confirmed and implemented. `flutter_secure_storage` is added to `pubspec.yaml` for that purpose, per [[../Security/Trust Anchors|Trust Anchors]].

**Not yet implemented:** actual device ECDSA P-256 keypair generation via platform Keystore/Keychain. This is cryptographic key-handling work — the debug screen is scaffolded, but generating and storing the real device keypair needs the specific plugin/approach confirmed before it's built (Flutter has no built-in hardware-backed asymmetric key generation; `flutter_secure_storage` alone only stores strings). See the open question logged in [[../stories/story-checkpoint-mvp|Story Checkpoint: MVP]].

Expected notes once more of the story lands:
- Roster screen (Task 7)
- PIN / biometric prompt flow (Task 6)
- Local verification module (the Dart-side counterpart to [[../Architecture/Offline Sign-In Flow|Offline Sign-In Flow]], Task 5)

## See Also

- [[../Index|Vault Index]]
- [[../Architecture/Architecture Index|Architecture Index]]
