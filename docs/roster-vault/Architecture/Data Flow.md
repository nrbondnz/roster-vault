# Data Flow

Step-by-step sequences for the flows in [[System Diagram]] — this page answers "what happens, in order," that one answers "what talks to what."

## Enrollment Flow

See also [[Enrollment Flow]] for the narrative version and [[../Security/Trust Anchors|Trust Anchors]] for the key material involved.

```
Real person taps "Add a person" on the roster (RosterScreen)
    │
    ▼
DeviceIdentityService.ensureDeviceIdentity()
  -- already exists after the first ever run on this device
     (ECDSA P-256, Android Keystore); generated once if not
    │
    ▼
LoginScreen -- real Cognito SRP sign-in
  (Amplify.Auth.signIn(username, password))
    │
    ▼
UserIdentityService.ensureUserKeyPair(userId)
  -- one ECDSA P-256 keypair per person per device, generated
     once, reused on every later enroll/refresh for this person
    │
    ▼
EnrollmentService.enroll(deviceId, devicePubKey, userPubKey)
    │
    ▼
Plain authenticated HTTP POST to the `enroll` AppSync mutation,
carrying the live Cognito ID token as the Authorization header
    │
    ▼
Enrollment Lambda (amplify/functions/enroll/handler.ts):
  1. GetItem any existing DeviceEnrollments row for this
     device+user, to preserve its epoch across re-enrollment
  2. Build the JWS payload (user_id, device_id, scopes, epoch,
     iat, exp -- 48h TTL)
  3. kms:Sign the header.payload signing input (ECDSA_SHA_256)
  4. Convert KMS's DER-encoded signature to the fixed 64-byte
     raw R‖S format JWS requires
  5. PutItem the updated DeviceEnrollments row
    │
    ▼
{token, epoch, expiresAt} returned to the app
    │
    ▼
TokenVerifier.verify(token, issuerPublicKeyPem)
  -- verified locally against the issuer's public key, baked
     into the app at build time (lib/services/issuer_public_key.dart)
  ├── invalid ──▶ enrollment fails, shown on screen
  └── valid, continue
    │
    ▼
EnrollmentService persists the token (flutter_secure_storage)
and separately persists the known epoch (see Sign-In Flow below
for why this has to be a separate value, not the token's own claim)
    │
    ▼
Person chooses a PIN
    │
    ▼
LocalUnlockService.setUpPin(userId, pin, token)
  -- see Encrypted Storage Flow below for exactly what this does
    │
    ▼
RosterRegistryService.addOrUpdateProfile(userId, displayName)
  -- this person now appears on the roster
```

## Sign-In Flow (Offline)

The actual hard requirement — see also [[Offline Sign-In Flow]] and [[../Security/Token Lifecycle and Revocation|Token Lifecycle and Revocation]] for why the epoch check works the way it does. Runs entirely inside `OfflineVerifier`, which has no `http`/Amplify import at all — not merely "reviewed to not call the network," enforced by construction.

```
OfflineVerifier.verify() is called with the recovered token,
the baked-in issuer public key, this device's id, the locally-
known epoch, this person's public key, and a challenge signer
    │
    ▼
1. Signature check: JWT.verify(token, ECPublicKey(issuerPublicKeyPem))
    │
    ├── invalid / tampered / wrong key ──▶ badSignature, stop here
    └── valid, continue
    │
    ▼
2. Expiry check (the token's own `exp` claim)
    │
    ├── expired ──▶ expired, stop here
    └── still valid, continue
    │
    ▼
3. Device-id check: does claims['device_id'] match this device's
   own DeviceIdentityService id?
    │
    ├── no ──▶ wrongDevice, stop here
    └── yes, continue
    │
    ▼
4. Epoch check: is claims['epoch'] < the epoch persisted on-device
   from this person's last successful enroll/refresh?
   -- deliberately NOT compared against the token's own epoch
      claim, which would make this check a tautology that always
      passes -- see Token Lifecycle and Revocation.md
    │
    ├── stale (token epoch older than known epoch) ──▶ staleEpoch, stop
    └── current or newer, continue
    │
    ▼
5. Challenge-response -- proves possession of the private key,
   not just a copied token blob:
    │
    ├── Generate a fresh random nonce
    │       │
    │       ▼
    ├── UserIdentityService.signChallenge(userId, nonce):
    │     1. Build the JWS signing input ({alg: ES256, typ: JWT}
    │        header + {nonce} payload)
    │     2. biometric_signature.createSignature() against this
    │        person's hardware-backed private key (Android Keystore)
    │     3. Plugin signs via plain JCA SHA256withECDSA -> DER-encoded
    │        (confirmed by reading the plugin's own source)
    │     4. Convert DER -> raw 64-byte R‖S (the same conversion the
    │        Enrollment Lambda already does for KMS's own DER output)
    │     5. Assemble into an ES256 JWS challenge response
    │       │
    │       ▼
    └── JWT.verify(challengeResponse, ECPublicKey(userPublicKeyPem))
            │
            ├── wrong signing key, or echoed nonce doesn't match
            │   the one just generated ──▶ challengeFailed, stop
            └── valid, nonce matches
    │
    ▼
OfflineVerificationResult.valid(claims) -- PASS, shown on screen
```

## Encrypted Storage Flow

How a PIN actually gates one person's data on a shared device — see also [[Multi-User Partitioning]] and [[System Diagram]]'s expanded `LocalUnlockService.unlock` box.

```
Person taps their name on the roster, enters their PIN
    │
    ▼
LocalUnlockService.unlock(userId, pin)
    │
    ▼
1. Derive K_user = HKDF(K_device, userId)
   -- deterministic, does NOT need the PIN as input; K_device is
      a dedicated random 256-bit secret (DeviceMasterKeyService),
      deliberately independent of the Trust Anchor 2 signing key
    │
    ▼
2. Open EncryptedPartitionStore(dbPath, K_user)
   -- package:sqlite3 3.x, the sqlite3mc cipher build (selected
      via pubspec.yaml's hooks.user_defines -- sqlcipher_flutter_libs
      is EOL upstream, sqlite3mc is the self-contained replacement
      with no OpenSSL dependency)
   -- this step succeeds regardless of whether the PIN entered is
      correct, since K_user doesn't depend on it -- see below for
      why that's the intended design, not a gap
    │
    ▼
3. Read the "wrapped_enrollment_token" row from that person's
   partition file
    │
    ▼
4. PinService.unwrap(pin, wrapped)
   -- key derived from the PIN via Argon2id (19 MiB memory,
      2 iterations -- OWASP's current minimum for a low-entropy
      secret), then AES-256-GCM authenticated decryption
    │
    ├── wrong PIN ──▶ authentication fails ──▶ returns null,
    │                 never a thrown error or garbage plaintext
    │                 ("Wrong PIN — rejected" on screen)
    └── correct PIN ──▶ the real enrollment token, ready to feed
                         into the Sign-In Flow above
```

Two-layer guarantee, stated precisely: raw file access alone (a lost tablet, a forensic pull with no device secrets) needs `K_device` to get anywhere, and device compromise alone (an attacker who *does* have `K_device`) still needs this specific person's PIN to recover their token. Neither alone is enough — demonstrated for real this session with two independently-enrolled profiles on the same device, each with a different PIN: one profile's PIN entered against the other's data was rejected, and each profile's own PIN correctly recovered only their own token.

## Airplane Mode Setup and Usage Flow

The literal real-world procedure that makes this whole project's core claim real rather than theoretical — the payoff step. This is also, concretely, what was actually run this session to verify [[Offline Sign-In Flow|Task 5]].

```
Real end-user path:                    This session's verification path:
────────────────────                   ──────────────────────────────────
Settings → Airplane Mode → On          adb shell cmd connectivity
                                          airplane-mode enable
    │                                       │
    ▼                                       ▼
Phone's Wi-Fi and cellular radios      Confirmed via:
physically disabled                      - adb shell settings get global
                                            airplane_mode_on -> "1"
                                          - the airplane icon replacing
                                            the Wi-Fi icon in the status bar
    │                                       │
    └───────────────────┬───────────────────┘
                         ▼
        Open Roster Vault, tap an enrolled profile
                         │
                         ▼
        Enter that profile's PIN
                         │
                         ▼
        Encrypted Storage Flow runs (above) -- reads the local,
        PIN-wrapped, K_user-encrypted partition; no network
        involved at any point in this step either
                         │
                         ▼
        Sign-In Flow runs (above) -- OfflineVerifier makes zero
        network calls by construction (no http/Amplify import
        anywhere in that class, not just "reviewed to not call
        the network")
                         │
                         ▼
        Result shown on screen: "Offline sign-in: PASS"
        (or a specific, named FAIL -- badSignature / expired /
        wrongDevice / staleEpoch / challengeFailed)
                         │
                         ▼
        Airplane mode switched back off
        (adb shell cmd connectivity airplane-mode disable in
        this session's case; confirmed back to "0")
```

Why this step matters more than it might look: everything above it in this page can be true of code that merely *avoids importing* networking packages while still depending, unnoticed, on some cached state that quietly assumes connectivity. The only way to actually rule that out is to remove connectivity and watch the flow still work — which is what this session did, on real hardware, not as a hypothetical.

## See Also

- [[Architecture Index]]
- [[System Diagram]] — the same flows as components-and-arrows, not steps
- [[System Overview]]
- [[Enrollment Flow]] · [[Offline Sign-In Flow]] · [[Multi-User Partitioning]]
