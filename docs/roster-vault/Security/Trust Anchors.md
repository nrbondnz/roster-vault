# Trust Anchors

Three pieces of key material carry the entire offline guarantee. Everything in [[../Architecture/Architecture Index|Architecture]] is plumbing around them.

## Anchor 1 — Issuer Key

Signs every offline capability token. Never touches app memory, and never touches Lambda memory as a private key either.

- **What it is:** a KMS asymmetric CMK, `ECC_NIST_P256`.
- **Where it lives:** AWS KMS. Signing happens via `kms:Sign`, called from the Enrollment Lambda. The private key material never leaves KMS.
- **What ships in the app:** only the **public** half, retrieved via `kms:GetPublicKey` at build/deploy time and baked into the app so signature verification is pure local math with no network call. See [[../../agents/review-agent/review-agent|Review Agent]] checklist item 1 — this distinction (public key shipped, private key never exportable) is the single most important thing to get right and keep right.
  - **Implemented in (Task 4a):** `lib/services/issuer_public_key.dart`, a checked-in PEM constant with the exact `kms get-public-key` + `openssl` regeneration command in its doc comment. Not yet consumed by any verification code (that's Task 5) — this task only issues tokens and bakes in the public key for the following task to use.
- **Signing implementation (Task 4a):** `amplify/functions/enroll/handler.ts` builds a standard ES256 JWS by hand (header + payload signed via `kms:Sign`, `SigningAlgorithm: ECDSA_SHA_256`). KMS returns the signature DER-encoded; JWS requires the raw fixed-width 64-byte `R‖S` format, so the handler does that conversion itself — the one non-obvious piece of wire-format code in the whole enrollment path.

## Anchor 2 — Device Keypair

Ties every token to *this* physical device, not just to a person.

- **What it is:** an ECDSA P-256 keypair, generated once, on first run.
- **Where it lives:** platform Keystore (Android) / Keychain-backed Secure Enclave (iOS) where hardware support exists; falls back to software-wrapped storage on weaker hardware — see [[Risk Register]] for the "unmanaged device" tradeoff this implies.
- **What's registered server-side:** only the public key, sent once during [[../Architecture/Enrollment Flow|Enrollment Flow]].
- **Implemented in (Task 3):** `lib/services/device_identity_service.dart`, via the `biometric_signature` plugin (`SignatureType.ecdsa`, key alias `roster_vault_device_key`, `CreateKeysConfig.requireAuthentication: false` — deliberate, since this key isn't gated by a person's local factor, only by the hardware). The plugin's API has no method that ever returns a private key; only the public key and signatures are ever exposed to Dart.
  - **Correctness note:** the plugin's `createKeys` silently *replaces* an existing key under the same alias unless checked for first (`failIfExists` defaults to `false`). The service always calls `getKeyInfo` before `createKeys` for exactly this reason — an unconditional call on every app start would otherwise rotate the device key underneath every already-issued token.
  - **Platform caveat:** on Windows, this plugin ignores the requested `signatureType` and always issues RSA-2048 instead (its own documented behavior). Windows is only used here as a convenient desktop dev target, not a deployment target.
  - **Android setup requirement:** `biometric_signature` requires `android/app/.../MainActivity.kt` to extend `FlutterFragmentActivity`, not the Flutter-template-default `FlutterActivity` (the plugin's own README documents this; it uses `androidx.biometric.BiometricPrompt` internally, which itself requires a `FragmentActivity`). Missing this produced a confusing-looking runtime error (`BiometricError.unknown "Foreground activity required"`, even with the app genuinely foregrounded and drawn) rather than a clear setup error — see [[../Troubleshooting/Known Issues|Known Issues]] for the full diagnosis. Already applied in this project.
  - **ECDSA P-256 guarantee: verified on real Android hardware (2026-09-10).** Real device key generated on a Samsung Galaxy A06 (Android 16 / API 36) — Device ID `fe8888db42d5c63fddb42e91291a0481`, public key `MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcD...` (short SPKI with the EC/P-256 OID prefix, distinct from the long RSA-2048 SPKI seen on Windows). This closes out the "still needs a real Android/iOS run" caveat that stood here previously.
  - **iOS readiness — scoped 2026-09-10, NOT yet verified on real hardware (no Mac available in this environment).** Read `BiometricSignaturePlugin.swift` directly rather than assuming: on a real iOS device, `createKeys(signatureType: .ecdsa)` — unchanged from what this project already calls — takes the `performEcSigning` path by default, a genuine Secure Enclave-backed P-256 key; the plugin's RSA path only exists to migrate installs from its own pre-v10 API, irrelevant to a fresh project. Signing uses `.ecdsaSignatureMessageX962SHA256`, which is DER-encoded (X9.62), the same shape as Android's `SHA256withECDSA` — `UserIdentityService`'s existing DER-to-raw conversion should carry over unchanged, though this still needs confirming on a real device, not assumed from source alone. Also confirmed: with `requireAuthentication: false` (this project's actual setting for both keys), the plugin deliberately omits any biometry/passcode access-control flag and uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so key creation should not require a device passcode to be set — the iOS analogue of the Windows-Hello/`FlutterFragmentActivity` class of problem, which this plugin appears to have designed around correctly. `NSFaceIDUsageDescription` added to `ios/Runner/Info.plist` ahead of need (Task 6's planned biometric-gated per-user credential path). See [[../Troubleshooting/Known Issues|Known Issues]] for the other iOS-readiness finding (Keychain survives app deletion) and its fix.

## Anchor 3 — Per-User Credential

Bound to one person, on one device, gated by that person's own local factor.

- **What it is:** a second ECDSA P-256 keypair, one per enrolled person per device.
- **Where it lives:** `flutter_secure_storage`, wrapped by a key derived from the person's PIN or unlocked via biometric.
- **What it's used for:** the challenge–response step in [[../Architecture/Offline Sign-In Flow|Offline Sign-In Flow]] — proving the person unlocking a token actually holds the matching private key, not just a copied token blob.

This is FIDO2-*inspired* — a per-user asymmetric credential plus challenge–response — not literal FIDO2/WebAuthn, which assumes a relying-party server verifying at time of use. Worth being precise about that distinction when describing this to a client; see [[Risk Register]].

## Why Three, Not One

A single shared secret can't do all three jobs at once:
- The **issuer key** has to prove tokens came from the real identity service, without ever being present on a device that could be extracted.
- The **device key** has to stop a token (or a copied local store) from working on a *different* device than the one it was issued to.
- The **per-user key** has to stop one enrolled person's credential from being usable by anyone but them, even on the correct device.

Collapsing any two of these into one key removes exactly one of those three guarantees.

## See Also

- [[Security Index]]
- [[../Architecture/System Overview|System Overview]]
- [[Token Lifecycle and Revocation]]
