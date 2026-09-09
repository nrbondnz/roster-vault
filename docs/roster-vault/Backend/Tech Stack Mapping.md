# Tech Stack Mapping

The part a generic architecture answer usually skips — what each piece of [[../Architecture/System Overview|System Overview]] actually *is*, concretely, in this stack.

| Requirement | AWS Amplify Gen 2 | Flutter |
|---|---|---|
| Online identity check | Cognito User Pool | `amplify_auth_cognito` |
| Enrollment / refresh API | AppSync mutation → Lambda resolver | `amplify_api` |
| Token signing | KMS asymmetric CMK (`ECC_NIST_P256`), signed via `kms:Sign` from Lambda | `dart_jsonwebtoken` (verify only — never signs) |
| Device / user / epoch records | DynamoDB — `DeviceEnrollments` table | — |
| Device & per-user keys | — | `flutter_secure_storage` over Android Keystore / iOS Keychain |
| Local unlock factor | — | `local_auth` (biometric) + Argon2id PIN fallback via `cryptography` |
| Per-user encrypted local data | — | `drift` + `sqlcipher_flutter_libs`, key = `HKDF(K_device, user_id)` |
| Reconnect / silent refresh trigger | — | `connectivity_plus`, hooked to app foreground |
| Root/jailbreak posture check | — | best-effort integrity check package, degrade not block |

## Why Cognito Only Does One Job Here

It's tempting to reach for Cognito's own token machinery (ID/access/refresh JWTs) to cover the offline case too. It doesn't fit: Cognito's tokens are designed around live introspection and standard OAuth refresh, not around per-device binding, an epoch-based revocation model, or a bounded offline validity window with no server round trip. Cognito proves identity *once, online* — see [[../Architecture/Enrollment Flow|Enrollment Flow]] — and everything downstream of that is a custom, KMS-signed token layer purpose-built for the offline case, per [[../Security/Trust Anchors|Trust Anchors]].

## Data Model (sketch, formalised in Phase 0)

`DeviceEnrollments` (DynamoDB):

| Field | Purpose |
|---|---|
| `deviceId` (PK) | The enrolled device's identifier |
| `userId` (SK) | One row per enrolled person per device |
| `devicePubKey` | Registered at first enrollment on this device |
| `userPubKey` | This person's per-device public key |
| `epoch` | Current epoch for this user; bumped on termination |
| `status` | active / inactive |
| `lastIssuedExpiry` | For visibility into how long a device could plausibly operate without reconnecting |

## See Also

- [[Backend Index]]
- [[../Architecture/System Overview|System Overview]]
- [[../Security/Trust Anchors|Trust Anchors]]
