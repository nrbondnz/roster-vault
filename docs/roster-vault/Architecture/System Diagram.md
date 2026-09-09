# System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SHARED DEVICE (offline-capable)                   │
│                                                                       │
│              ┌───────────────────────────────────────┐              │
│              │     RosterScreen (real app entry)      │              │
│              │  RosterRegistryService.listProfiles()  │              │
│              │            -- local only                │              │
│              └───────────────┬───────────────┬────────┘              │
│                      tap a name│               │"Add a person"       │
│                               ▼               │(greyed out offline)  │
│              ┌──────────────────────────┐     ▼                     │
│              │   PIN prompt dialog       │  ┌──────────────────┐     │
│              └────────────┬──────────────┘  │ AuthGate ->       │     │
│                            │ pin             │ LoginScreen       │     │
│                            ▼                 │ (real Cognito    │     │
│              ┌──────────────────────────┐    │  SRP sign-in)    │     │
│              │  LocalUnlockService        │  └────────┬──────────┘     │
│              │  .unlock(userId, pin)      │           │                │
│              └────────────┬───────────────┘           ▼                │
│                            │                 see ENROLLMENT FLOW       │
│                    token or null                       below           │
│                            ▼                                          │
│              ┌──────────────────────────┐                             │
│              │   ProfileHomeScreen        │  see OFFLINE VERIFICATION  │
│              │   runs OfflineVerifier     │  FLOW below                │
│              └──────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────┘
```

`LocalUnlockService.unlock(userId, pin)`, expanded:

```
1. Derive K_user = HKDF(K_device, userId)
   -- no PIN needed for this step, by design (see below)
        │
        ▼
2. Open EncryptedPartitionStore(dbPath, K_user)
   -- sqlite3 3.x, sqlite3mc cipher build
        │
        ▼
3. Read the wrapped-enrollment-token row
        │
        ▼
4. PinService.unwrap(pin, wrapped) -- Argon2id-derived key
   ├── wrong PIN  ──▶ null ("Wrong PIN — rejected")
   └── correct PIN ──▶ the real enrollment token
```

Why the PIN wraps the token instead of the database key: `K_user` alone only needs `K_device` (itself just OS-encrypted) to derive — no PIN required. Wrapping the token with an Argon2id-derived, PIN-only key gives the PIN a genuine, separate job: raw file theft alone (needs `K_device`) and device compromise alone (needs the PIN) both fail; only both together succeed. "Sign Out" in `ProfileHomeScreen` is just `Navigator.pop` back to the roster — no round trip, no re-derivation, since nothing was ever "open" beyond that screen's own local variables (Task 7's Fast Switching guarantee).

## Enrollment Flow (Backend)

The one part of the system that needs a network — see [[Enrollment Flow]] for the narrative version.

```
Flutter app                          AWS Amplify Gen 2 (online only)
────────────                         ────────────────────────────────

DeviceIdentityService
  .ensureDeviceIdentity()
  (ECDSA P-256, Android Keystore --
   generated once, reused after)
        │
        ▼
UserIdentityService
  .ensureUserKeyPair(userId)
  (ECDSA P-256, one per person
   per device)
        │
        ▼
LoginScreen -- real Cognito SRP
  sign-in via Amplify.Auth.signIn()  ──────▶  Cognito User Pool
                                               (ap-southeast-2_B1k3XjP8l)
        │ ID token
        ▼
EnrollmentService.enroll(deviceId,
  devicePubKey, userPubKey)
  -- plain authenticated HTTP POST    ──────▶  AppSync (roster-vault-
  (NOT amplify_api -- enroll is a               enrollment-api)
  custom endpoint outside Amplify's             Cognito User Pool
  `data` category)                              authorizer verifies
                                                 the ID token first
                                                        │
                                                        ▼
                                               ┌──────────────────────┐
                                               │  Enrollment Lambda     │
                                               │  (amplify/functions/   │
                                               │   enroll/handler.ts)   │
                                               │                        │
                                               │  1. GetItem existing   │
                                               │     DeviceEnrollments  │
                                               │     row (preserve      │
                                               │     epoch across       │
                                               │     re-enrollment)     │
                                               │  2. kms:Sign a JWS     │
                                               │     (ES256, hand-      │
                                               │     built header.     │
                                               │     payload.sig) ─────┼──▶ KMS issuer
                                               │  3. DER→raw R‖S        │   signing key
                                               │     conversion (KMS's  │   (SIGN_VERIFY
                                               │     own DER output ->  │    only)
                                               │     fixed 64-byte      │
                                               │     JWS format)        │
                                               │  4. PutItem            │
                                               │     DeviceEnrollments  ├──▶ DynamoDB
                                               └───────────┬────────────┘
                                                            │ {token, epoch, expiresAt}
        ◀───────────────────────────────────────────────────┘
        │
        ▼
TokenVerifier.verify(token,
  issuerPublicKeyPem)
  -- verified locally against the
  public key baked into the app at
  build time (issuer_public_key.dart)
        │
        ▼
EnrollmentService persists:
  - the token (flutter_secure_storage)
  - the known epoch (separately --
    see OFFLINE VERIFICATION FLOW)
        │
        ▼
LocalUnlockService.setUpPin() wraps
  the token with a PIN and stores it
  inside the person's own K_user-
  encrypted partition
```

## Offline Verification Flow

Zero network calls, enforced by construction (`OfflineVerifier` has no `http`/Amplify import at all) — see [[Offline Sign-In Flow]] for the narrative version and [[../Security/Token Lifecycle and Revocation|Token Lifecycle and Revocation]] for why the epoch check compares against a locally-persisted value, not the token's own claim.

```
OfflineVerifier.verify(token, issuerPublicKeyPem,
  expectedDeviceId, currentKnownEpoch,
  userPublicKeyPem, signChallenge)
        │
        ▼
1. Signature check
   JWT.verify(token, ECPublicKey(issuerPublicKeyPem))
   ├── invalid/tampered ──▶ badSignature
   └── valid, continue
        │
        ▼
2. Expiry check (from the JWS itself)
   ├── expired ──▶ expired
   └── still valid, continue
        │
        ▼
3. Device-id check
   claims['device_id'] == this device's DeviceIdentityService id?
   ├── no ──▶ wrongDevice
   └── yes, continue
        │
        ▼
4. Epoch check
   claims['epoch'] < EnrollmentService's locally-persisted
   knownEpoch (NOT the token's own epoch claim -- that would
   make this check a tautology that always passes)?
   ├── stale ──▶ staleEpoch
   └── current or newer, continue
        │
        ▼
5. Challenge-response
   Generate a fresh random nonce
        │
        ▼
   UserIdentityService.signChallenge(userId, nonce)
     -- biometric_signature.createSignature() against the
        person's hardware-backed key (Android Keystore)
     -- signs via plain JCA SHA256withECDSA -> DER-encoded
     -- converted DER -> raw 64-byte R‖S (same conversion
        the Lambda already does for KMS's own DER output)
     -- assembled into an ES256 JWS challenge response
        │
        ▼
   JWT.verify(challengeResponse, ECPublicKey(userPublicKeyPem))
   ├── wrong key, or echoed nonce doesn't match ──▶ challengeFailed
   └── valid, nonce matches
        │
        ▼
   OfflineVerificationResult.valid(claims) -- PASS
```

## See Also

- [[Architecture Index]]
- [[System Overview]] — the actors/roles narrative this diagram makes concrete
- [[Data Flow]] — the same flows as linear, step-by-step sequences
- [[Enrollment Flow]] · [[Offline Sign-In Flow]] · [[Multi-User Partitioning]]
