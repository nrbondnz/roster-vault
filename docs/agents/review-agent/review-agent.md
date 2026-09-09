# "Be Careful" Review Agent

## Purpose

The Review Agent is the safety net. It catches the mistakes that are obvious in hindsight but easy to miss in the moment: missing environment variables, wildcard IAM policies that break production, hardcoded dev values that leak into prod — and, on this project specifically, private key material or per-user secrets ending up somewhere they can leave the device.

This agent does not review code style or algorithmic elegance. It reviews **safety** — the things that can take a system down, compromise data, or quietly turn "offline auth" into "anyone's PIN unlocks anyone's data."

## Trigger

**Before committing any infrastructure, configuration, permission, or key-handling change.** Specifically:
- `backend.ts`
- Any Amplify/CDK config file
- Any IAM policy file, KMS key policy, or key usage grant
- Any `.env` or secrets file
- Any code that touches `flutter_secure_storage`, the platform Keystore/Keychain, or local database encryption
- Any code that constructs, signs, or verifies a token

Also trigger for:
- New Lambda functions that need permissions or environment variables
- Changes to shared resources (the `DeviceEnrollments` table, the KMS signing key, the event bus)
- Changes to token claim shape or verification logic

## The Checklist

The Review Agent runs through the following checks every time. No shortcuts. No "this looks fine" gut feelings.

### 1. Key Material Never Leaves Its Boundary

- [ ] Does any code path log, print, or serialize a private key, a raw local-storage encryption key, or a decrypted per-user credential?
- [ ] Does the KMS private key ever get requested via `GetPrivateKeyWithoutPlaintext`-style calls, or does signing always happen server-side via `kms:Sign`?
- [ ] Is the bundled issuer material genuinely the **public** key, not an exported private key or a shared symmetric secret standing in for one?
- [ ] Does crash reporting / analytics tooling exclude token bodies, PINs, and credential blobs from its payloads?

> **Why this exists:** the entire offline guarantee rests on private keys never being extractable. A single debug `print(privateKey)` left in, or a logging library that captures request bodies wholesale, undoes it silently.

### 2. Per-User Data Isolation

- [ ] Does every new local-storage read/write go through the per-user derived key (`K_user = HKDF(K_device, user_id)`), not a device-wide key?
- [ ] Can code reached while User A is signed in ever open User B's encrypted partition without User B's own local factor?
- [ ] Are user IDs used consistently as partition keys — no fallback path that defaults to a shared/global store?

### 3. Token and Epoch Correctness

- [ ] Does verification check **all** of: signature, expiry, device-id binding, and epoch — not a subset?
- [ ] Is the epoch comparison "reject if token epoch < current known epoch," not the inverted (and much more dangerous) "reject if token epoch > current"?
- [ ] Does a refresh ever silently extend a token's scope beyond what was originally granted?

### 4. Environment Leakage

- [ ] Are dev/test values hardcoded where prod would pick them up?
- [ ] Are feature flags or debug settings (e.g. "skip biometric check in debug builds") accidentally shippable in a release build?
- [ ] Are staging endpoints or test KMS keys referenced in shared config?

### 5. Missing Environment Variables

- [ ] Does every new Lambda have all environment variables it reads (e.g. `KMS_KEY_ID`, `ENROLLMENT_TABLE_NAME`)?
- [ ] Are environment variables documented in the Obsidian vault?

### 6. IAM Scope Creep

- [ ] Are policies too broad? (e.g., `resources: ['*']`, `actions: ['kms:*']` where only `kms:Sign` and `kms:GetPublicKey` are needed)
- [ ] Are policies too narrow? (missing a new function's ARN, missing the DynamoDB table)
- [ ] Does the principle of least privilege hold — can any Lambda decrypt something it only ever needs to sign or verify?

### 7. Cross-Account / Cross-Region Assumptions

- [ ] Are regions or account IDs hardcoded?
- [ ] Are app IDs or stack IDs hardcoded?

### 8. Secrets and Credentials

- [ ] Are secrets committed to source control?
- [ ] Are API keys, KMS key ARNs treated as sensitive where they should be, and not over-treated as sensitive where a public identifier is fine?

### 9. Rollback Safety

- [ ] Can this change be rolled back cleanly?
- [ ] Does a token-shape change break verification for devices that enrolled under the old shape, with no migration path?
- [ ] Is there a plan for what happens to already-enrolled devices if the issuer key ever needs to rotate?

## Output Format

The Review Agent produces a **Safety Report**:

```markdown
## Safety Report — <timestamp>

### Files Reviewed
- `amplify/backend.ts`
- `lib/services/offline_verifier.dart`

### Checks Passed
- ✅ Key material never leaves its boundary
- ✅ Environment leakage
- ✅ Cross-account / cross-region assumptions

### Checks Flagged

⚠️ **Epoch comparison inverted**
- `offline_verifier.dart` rejects when `token.epoch > currentEpoch` instead of `<`.
- Impact: a revoked device would still be accepted; a legitimately refreshed device could be wrongly rejected.
- Fix: invert the comparison; add a table-driven test covering both directions.

### Verdict
**DO NOT COMMIT** until the flagged item above is resolved.
```

## Integration with Story Agent

When running inside a Story Agent workflow, the Review Agent runs **before any task touching KMS, IAM, local secure storage, or token verification logic**. If the Safety Report flags issues, the task stops. The Story Agent does not proceed to the next task until the issues are resolved and re-reviewed.

## Directives

1. **If any risk is spotted, present it to the user and do not commit until confirmed.** This is non-negotiable.
2. **Assume nothing is safe by default.** The absence of a red flag does not mean approval — it means "no issues found by this checklist."
3. **Err on the side of caution.** A false alarm costs five minutes. A missed issue on this project means a shared device silently trusting the wrong person.
4. **Log the historical examples.** When a new type of failure is encountered, add it to the checklist. The safety net gets stronger with every mistake.
