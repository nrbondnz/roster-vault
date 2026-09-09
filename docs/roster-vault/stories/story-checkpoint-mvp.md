# Story Checkpoint: Roster Vault MVP

## Story Goal

Build a working, demonstrable version of offline multi-user authentication on a shared, unmanaged device: enroll a person while online, then prove they can sign in — and a second person can sign in as themselves — with the device's network switched off.

## Complexity Score

12 (Large — full Story Agent protocol mandatory)

Crosses 4+ architectural layers (Flutter → AppSync → Lambda → KMS → DynamoDB), involves genuine cryptographic design, has 3+ real conditional branches in the verification logic alone (expired / wrong device / stale epoch), requires new infrastructure and IAM policy, and has well over 3 acceptance criteria. See [[../../agents/story-agent/story-agent|Story Agent]] for the scoring rubric.

## Status

IN PROGRESS — Task 0 and Task 2 complete. Task 1 BLOCKED (needs Nigel to create the GitHub repo). Task 3 IN PROGRESS (Flutter scaffold done; device keypair generation paused on an open crypto-approach question).

---

## Task 0: Documentation and architecture in place
- **Status:** COMPLETE
- **What changed:** Set up the Obsidian vault at `docs/roster-vault/`, carried the agent-driven workflow over from `where_in_nz_v3` (`docs/agents/`), and wrote the full architecture: trust anchors, enrollment flow, offline sign-in flow, multi-user partitioning, token lifecycle and epoch model, risk register, and the concrete AWS Amplify Gen 2 / Flutter tech-stack mapping.
- **Verified by:** Reviewed by Nigel.
- **Files changed:** everything under `docs/agents/` and `docs/roster-vault/` — see [[../Index|Vault Index]] for the full map.
- **Checkpoint saved:** 2026-09-09

## Task 1: GitHub repository and Amplify Hosting git connection
- **Status:** BLOCKED — waiting on Nigel
- **Setup:** None — can happen alongside Task 2, but has to land before Amplify Hosting can build anything from a branch push (local `ampx sandbox` work doesn't need it, but the team/CI build path does).
- **Work:** Create a GitHub repository, push this repo's history to it on `main`, and connect that repo as the git provider for Amplify Gen 2 Hosting so a push triggers a hosted backend build — not just a locally-run `ampx sandbox`.
- **Verify:** A push to `main` triggers a build in the Amplify Console for this app, and it completes successfully.
- **Save:** Repo URL and Amplify Hosting app ID recorded in [[../Build and Deploy/Build and Deploy Index|Build and Deploy Index]].
- **Depends on:** Task 0
- **Blocked on:** Nigel chose "you create it, I push" for this task. No `gh` CLI is installed and there's no remote yet — need the empty repo's URL (and confirmation of name/visibility) before this can proceed. Nothing has been committed to git yet, on purpose, so there's no risk of losing work in the meantime.

## Task 2: Amplify Gen 2 skeleton
- **Status:** COMPLETE
- **What changed:** `npm create-amplify` scaffold, with the default `data` (Todo/guest-CRUD demo) resource deleted — not part of this project's design and not something to leave deployed even to a sandbox. `amplify/backend.ts` defines Cognito (`defineAuth`, email login) plus a nested `RosterVaultCore` CDK stack holding the KMS issuer signing key (`ECC_NIST_P256`, `SIGN_VERIFY` only, alias `alias/roster-vault-issuer-signing-key`) and the `DeviceEnrollments` DynamoDB table (`deviceId` PK / `userId` SK, on-demand billing). Deployed via `npx ampx sandbox --once`.
- **Verified by:** `aws kms get-public-key` against the deployed key, followed by `aws kms sign` (ECDSA_SHA_256, outside app code) on a test message, verified locally with `openssl dgst -verify` against the fetched public key — signature verified OK. Full identifiers in [[../Backend/Backend Index|Backend Index]].
- **Files changed:** `package.json`, `package-lock.json`, `amplify/backend.ts`, `amplify/auth/resource.ts`, `amplify/package.json`, `amplify/tsconfig.json` (deleted `amplify/data/resource.ts`), `amplify_outputs.json` (generated, gitignored), plus `docs/roster-vault/Backend/Backend Index.md` and `docs/roster-vault/Build and Deploy/Build and Deploy Index.md`.
- **Checkpoint saved:** 2026-09-09
- **Review Agent (self-run, since this touched a KMS key and its IAM surface):** Checked against the full checklist — key usage is sign/verify only (no decrypt path exists), private key never requested or logged, no `kms:*`/wildcard grants exist yet (none needed until Task 4's Lambda), no hardcoded region/account, no secrets committed. One flagged-and-accepted item: both the KMS key and table use `RemovalPolicy.DESTROY` (7-day pending window on the key) rather than `RETAIN`, since no device is enrolled yet — documented in Backend Index as a **must switch to RETAIN before any deploy with live enrolled devices**. Verdict: safe to proceed.

## Task 3: Flutter project scaffold and device identity
- **Status:** IN PROGRESS
- **Setup:** Task 2 complete (need the sandbox to enroll against later, though this task itself doesn't call it yet).
- **Work:** `flutter create` done — project `roster_vault` (org `com.rostervault`), targeting Android/iOS/Windows. Real home screen (`DeviceDebugScreen`, not the default counter demo) in place. `flutter_secure_storage` added to `pubspec.yaml`. **Not yet done:** actual device ECDSA P-256 keypair generation and `deviceId` persistence — see open question below.
- **Verify so far:** **First on-screen Flutter milestone, partially met:** `flutter analyze` and `flutter test` both clean/passing. `flutter build windows --debug` succeeded — `build\windows\x64\runner\Debug\roster_vault.exe` exists and links correctly. Launching it to actually watch it render is left for Nigel when he's back, since that's the point of an on-screen milestone. Device keypair generation itself is not yet built, so the "public key readable, private key never exposed" verification can't happen yet.
- **Save:** Flutter project scaffold exists at the repo root; debug screen shows placeholder text until keypair generation lands.
- **Depends on:** Task 2
- **Open question, researched, awaiting confirmation before implementing:** Flutter has no built-in hardware-backed asymmetric key generation. Nigel chose "vet a maintained plugin first." Researched candidates: `keystore_plugin` (supports it, but last published ~12 months ago, 1 like — looks under-maintained), `flutter_secp256r1` (pub.dev page 404s, couldn't verify), `biometric_crypto` and `synheart_auth` (not yet vetted in depth). **Leading candidate: `biometric_signature`** — verified publisher (visionflutter.com), actively maintained (published 46 days ago, v13), 160 pub points / 54 likes / 28.7k downloads, MIT license. Confirmed via its README: hardware-backed P-256 keys via Android Keystore/StrongBox and iOS Secure Enclave, signing happens in hardware without exposing the private key to Dart, supports multiple named keys via a `keyAlias` parameter (one call could cover both the single device key here in Task 3 *and* the per-user keys in Task 6), public key export as base64/PEM/hex for sending to the enrollment Lambda, SHA-256 hashing handled internally, and biometric gating is optional per key (`requireAuthentication`) — needed off for the device key (no person-specific factor at this layer) but this reuse is exactly what Task 6 needs turned on. Not yet added to `pubspec.yaml` or implemented — holding for Nigel's go-ahead given this is a Trust Anchor implementation choice.

## Task 4: Enrollment flow, end to end (online)
- **Status:** NOT STARTED
- **Setup:** Tasks 2 and 3 complete.
- **Work:** Full [[../Architecture/Enrollment Flow|Enrollment Flow]] — a real login screen for Cognito OIDC, per-user keypair generation, the `enroll` AppSync mutation, KMS-signed token issuance, encrypted local storage of the result, PIN/biometric setup for that profile.
- **Verify:** **Second on-screen milestone:** a real person taps through an actual login screen, signs in online, and watches enrollment complete — the app shows a valid, correctly-signed offline token stored locally (inspectable in a debug view). Confirmed against the deployed sandbox from Task 2, not mocked.
- **Save:** One real enrolled profile exists on a test device.
- **Depends on:** Task 3

## Task 5: Offline verification (the core hard part)
- **Status:** NOT STARTED
- **Setup:** Task 4 complete — at least one enrolled profile with a stored token exists.
- **Work:** The [[../Architecture/Offline Sign-In Flow|Offline Sign-In Flow]] verification module: signature check against the bundled issuer public key, expiry check, device-id check, epoch check, challenge–response with the local private key. Since the full PIN/roster UI doesn't land until Tasks 6–7, this task adds a minimal debug-screen trigger (a "sign in" button against the one enrolled profile) so the airplane-mode result is visible on screen now rather than only inferred from logs.
- **Verify:** **Third on-screen milestone, with the device in airplane mode:** tapping the debug sign-in button shows a clear pass/fail result on screen. The enrolled profile signs in successfully. A token manually altered or re-signed with a different key is visibly rejected. A token with an expired timestamp is visibly rejected. This is the one task in the whole story where "the code looks right" is explicitly not sufficient — see the [[../../agents/story-agent/story-agent|Story Agent]]'s directive on proving offline claims.
- **Save:** Offline sign-in demonstrably works with connectivity disabled.
- **Depends on:** Task 4
- **Spawns:** [[../../agents/test-agent/test-agent|Test Agent]] for table-driven tests across all four check types, independently and in combination.

## Task 6: Local unlock factor and per-user encrypted storage
- **Status:** NOT STARTED
- **Setup:** Task 5 complete.
- **Work:** PIN entry UI with Argon2id-derived key wrapping; biometric path via `local_auth` where hardware supports it, replacing Task 5's debug-button trigger. Per-user encrypted local database (`drift` + `sqlcipher_flutter_libs`), keyed by `HKDF(K_device, user_id)` per [[../Architecture/Multi-User Partitioning|Multi-User Partitioning]].
- **Verify:** **Fourth on-screen milestone:** a real PIN pad (or biometric prompt) replaces the debug button. Two enrolled profiles on one device; profile A's data is not readable through profile B's session, confirmed by attempting cross-access, not just by inspecting the code path. Wrong PIN is visibly rejected on screen; correct PIN or biometric unlocks.
- **Save:** Two independently-encrypted profile partitions exist on one test device.
- **Depends on:** Task 5

## Task 7: Roster UI and multi-user switching
- **Status:** NOT STARTED
- **Setup:** Task 6 complete.
- **Work:** Roster screen listing enrolled profiles on this device — the actual "pick your name" surface the requirement describes. Fast switch: sign out locks the current partition and returns to the roster with no network round trip.
- **Verify:** **Fifth on-screen milestone:** the app opens to a real roster screen (names, not a debug list) with two enrolled profiles. A user can tap between them repeatedly, offline, each time landing in the correct person's data. This is the first point in the story where the app looks like the thing being sold to a client.
- **Save:** Full multi-user offline flow demonstrable end to end.
- **Depends on:** Task 6

## Task 8: Epoch, revocation, and silent refresh
- **Status:** NOT STARTED
- **Setup:** Task 7 complete.
- **Work:** Epoch field on `DeviceEnrollments`, bumped via an admin action. Silent refresh on app foreground when online, per [[../Security/Token Lifecycle and Revocation|Token Lifecycle and Revocation]]. Verification's epoch check (Task 5) wired to actually gate on this. Surface refresh outcome per profile on the roster/debug screen (e.g. a small "refreshed" / "refused" indicator) so revocation is something you watch happen, not something you infer from logs.
- **Verify:** **Sixth on-screen milestone:** bump a test user's epoch server-side while their device is offline — they remain signed in until token expiry (expected, documented behaviour), and the roster screen shows nothing has changed for them yet. Bring the device online; the screen visibly shows that user's refresh being refused, while other enrolled users on the same device show a normal refresh.
- **Save:** Revocation-by-epoch demonstrated, including the documented offline-window limitation.
- **Depends on:** Task 7

## Task 9: Hardening
- **Status:** NOT STARTED
- **Setup:** Task 8 complete.
- **Work:** Clock-rollback defence (persisted high-water-mark timestamp check). Best-effort root/jailbreak detection with graceful degradation, not a hard block. Lockout after repeated failed local-factor attempts, tracked per profile.
- **Verify:** **Seventh on-screen milestone:** setting the device clock backward produces a visible, specific on-screen message and blocks sign-in — not a silent failure. Repeated wrong PINs show a visible lockout state for that profile without affecting other enrolled profiles on the same device.
- **Save:** [[../Security/Risk Register|Risk Register]] mitigations for rows 1, 2, and 3 all demonstrated, not just designed.
- **Depends on:** Task 8

## Task 10: End-to-end testing and traceability review
- **Status:** NOT STARTED
- **Setup:** All previous tasks complete.
- **Work:** Full test suite run. [[../../agents/traceability-agent/traceability-agent|Traceability Agent]] pass against [[../Management/The Actual Requirement|The Actual Requirement]] and the acceptance criteria implied by each task above.
- **Verify:** All tests pass. Traceability matrix shows no gaps, or gaps are explicitly logged as known follow-ups.
- **Save:** Story marked DONE.
- **Depends on:** Task 9

---

## Plan Changes Log

- **2026-09-09:** Initial plan drafted from the architecture note, decomposed into 9 tasks (0 documentation + 8 build tasks) per Story Agent scoring (12, Large).
- **2026-09-09:** Scope change — inserted a new Task 1 (GitHub repository + Amplify Hosting git connection) ahead of the Amplify Gen 2 skeleton. Amplify's hosted backend build pipeline requires a connected git provider; the repo had no remote and no commits yet. All subsequent tasks renumbered (old Task 1 → 2, ... old Task 9 → 10). Flagged by Nigel mid-Task-1-execution, before any AWS deploy happened.

---

## Notes

- No code has been written yet — this checkpoint exists so that Task 1 can start from an approved plan, per the Story Agent's "no code during planning" rule.
- Task 5 is the one to protect most carefully against being rushed or merged with another task — it's the actual hard requirement, and everything before it is enabling infrastructure.
- Revisit the TTL length (currently assumed 24–72h) once there's a real sense of how often these devices actually reconnect — it's a policy knob, not fixed by the architecture.
- **Flutter demo progression, at a glance** (added 2026-09-09 at Nigel's request — he wants to see the app actually take shape, not just infra land):
  1. Task 3 — app runs, shows device ID + device public key
  2. Task 4 — real OIDC login screen, enrollment completes on screen
  3. Task 5 — debug "sign in" button, pass/fail visible in airplane mode
  4. Task 6 — real PIN pad / biometric prompt replaces the debug button
  5. Task 7 — real roster screen, tap-to-switch between two people
  6. Task 8 — roster shows per-profile refresh/refuse outcome after a revocation
  7. Task 9 — visible on-screen block for clock rollback and for lockout
