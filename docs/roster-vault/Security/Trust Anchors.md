# Trust Anchors

Three pieces of key material carry the entire offline guarantee. Everything in [[../Architecture/Architecture Index|Architecture]] is plumbing around them.

## Anchor 1 — Issuer Key

Signs every offline capability token. Never touches app memory, and never touches Lambda memory as a private key either.

- **What it is:** a KMS asymmetric CMK, `ECC_NIST_P256`.
- **Where it lives:** AWS KMS. Signing happens via `kms:Sign`, called from the Enrollment Lambda. The private key material never leaves KMS.
- **What ships in the app:** only the **public** half, retrieved via `kms:GetPublicKey` at build/deploy time and baked into the app so signature verification is pure local math with no network call. See [[../../agents/review-agent/review-agent|Review Agent]] checklist item 1 — this distinction (public key shipped, private key never exportable) is the single most important thing to get right and keep right.

## Anchor 2 — Device Keypair

Ties every token to *this* physical device, not just to a person.

- **What it is:** an ECDSA P-256 keypair, generated once, on first run.
- **Where it lives:** platform Keystore (Android) / Keychain-backed Secure Enclave (iOS) where hardware support exists; falls back to software-wrapped storage on weaker hardware — see [[Risk Register]] for the "unmanaged device" tradeoff this implies.
- **What's registered server-side:** only the public key, sent once during [[../Architecture/Enrollment Flow|Enrollment Flow]].
- **Implemented in (Task 3):** `lib/services/device_identity_service.dart`, via the `biometric_signature` plugin (`SignatureType.ecdsa`, key alias `roster_vault_device_key`, `CreateKeysConfig.requireAuthentication: false` — deliberate, since this key isn't gated by a person's local factor, only by the hardware). The plugin's API has no method that ever returns a private key; only the public key and signatures are ever exposed to Dart.
  - **Correctness note:** the plugin's `createKeys` silently *replaces* an existing key under the same alias unless checked for first (`failIfExists` defaults to `false`). The service always calls `getKeyInfo` before `createKeys` for exactly this reason — an unconditional call on every app start would otherwise rotate the device key underneath every already-issued token.
  - **Platform caveat:** on Windows, this plugin ignores the requested `signatureType` and always issues RSA-2048 instead (its own documented behavior). Windows is only used here as a convenient desktop dev target, not a deployment target — verifying the actual ECDSA P-256 guarantee requires running on Android or iOS.

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
