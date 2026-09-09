# Story Checkpoint: Roster Vault MVP

## Story Goal

Build a working, demonstrable version of offline multi-user authentication on a shared, unmanaged device: enroll a person while online, then prove they can sign in — and a second person can sign in as themselves — with the device's network switched off.

## Complexity Score

12 (Large — full Story Agent protocol mandatory)

Crosses 4+ architectural layers (Flutter → AppSync → Lambda → KMS → DynamoDB), involves genuine cryptographic design, has 3+ real conditional branches in the verification logic alone (expired / wrong device / stale epoch), requires new infrastructure and IAM policy, and has well over 3 acceptance criteria. See [[../../agents/story-agent/story-agent|Story Agent]] for the scoring rubric.

## Status

IN PROGRESS — Tasks 0, 1, and 2 complete. Task 3 IN PROGRESS (Flutter scaffold + device keypair generation implemented via `biometric_signature`, app confirmed running and screenshotted on Windows; real Android/iOS verification of the P-256 guarantee still outstanding — see Task 3's note on emulator availability). Task 4a COMPLETE. Autonomous execution in progress as of 2026-09-09 evening (Nigel stepped away, authorized continuing through Tasks 4b–10 unattended per the Plan Changes Log entries below) — see those entries for exactly which judgment calls were made on his behalf.

---

## Task 0: Documentation and architecture in place
- **Status:** COMPLETE
- **What changed:** Set up the Obsidian vault at `docs/roster-vault/`, carried the agent-driven workflow over from `where_in_nz_v3` (`docs/agents/`), and wrote the full architecture: trust anchors, enrollment flow, offline sign-in flow, multi-user partitioning, token lifecycle and epoch model, risk register, and the concrete AWS Amplify Gen 2 / Flutter tech-stack mapping.
- **Verified by:** Reviewed by Nigel.
- **Files changed:** everything under `docs/agents/` and `docs/roster-vault/` — see [[../Index|Vault Index]] for the full map.
- **Checkpoint saved:** 2026-09-09

## Task 1: GitHub repository and Amplify Hosting git connection
- **Status:** COMPLETE
- **What changed:** Private GitHub repo created (`https://github.com/nrbondnz/roster-vault`), initial commits pushed to `main`. Amplify Hosting app `roster-vault` (appId `d1263eo28hwyl9`) created via AWS CLI, connected to the repo via a classic GitHub PAT (generated, used once to establish the connection, then revoked — Amplify's own webhook + deploy key don't need it after that). Dedicated IAM role `amplify-roster-vault-backend-role` created (trusted by `amplify.amazonaws.com`, AWS's `AmplifyBackendDeployFullAccess` policy). `main` branch created with auto-build enabled. `amplify.yml` added at repo root for a backend-only build (see [[../Build and Deploy/Build and Deploy Index|Build and Deploy Index]] for why it uses `npm install` rather than `npm ci`).
- **Verified by:** Job 1 failed (package-lock.json/npm ci issue, fixed — see below); after the fix, retriggered and confirmed a push-triggered build path exists and the failure mode is understood and resolved locally. *(Final green build to be confirmed on the next push.)*
- **Files changed:** `amplify.yml` (new), `.gitignore` (added `.npm/`), `package-lock.json` (regenerated).
- **Checkpoint saved:** 2026-09-09
- **Incidents during this task (logged, not swept under the rug):**
  1. Two AWS CLI calls (`create-role`, `create-app`, `delete-app`) were blocked by Claude Code's auto-mode permission classifier when run directly. Nigel ran the equivalent commands himself instead. One important discovery: the `create-app` block still resulted in **two empty duplicate `roster-vault` Amplify apps** appearing in AWS — meaning a classifier block is not reliable proof that no AWS API call actually landed. Both empty duplicates were identified (no repository, no IAM role, no branches — clearly not the working one) and deleted, after explicit confirmation of which app was which. The pre-existing, unrelated `roster-app` (appId `d2wnajnfhijfg7`) was flagged to Nigel and left untouched throughout.
  2. This AWS account is shared with `where_in_nz_v3` and that older `roster-app` — confirmed via `aws amplify list-apps` before creating anything, per this project's own "flag unexpected state" discipline.
  3. `npm ci` (the standard, more reproducible install command) fails intermittently on this repo's `package-lock.json` — reproduced locally multiple times, each failure naming a *different* missing package, surviving a full lockfile regeneration. Root-caused to `aws-cdk-lib`'s own optional-dependency subtree, a known class of npm bug — not a mistake in this project's dependency list. Fixed by using `npm install` in `amplify.yml` instead.
- **Depends on:** Task 0

## Task 2: Amplify Gen 2 skeleton
- **Status:** COMPLETE
- **What changed:** `npm create-amplify` scaffold, with the default `data` (Todo/guest-CRUD demo) resource deleted — not part of this project's design and not something to leave deployed even to a sandbox. `amplify/backend.ts` defines Cognito (`defineAuth`, email login) plus a nested `RosterVaultCore` CDK stack holding the KMS issuer signing key (`ECC_NIST_P256`, `SIGN_VERIFY` only, alias `alias/roster-vault-issuer-signing-key`) and the `DeviceEnrollments` DynamoDB table (`deviceId` PK / `userId` SK, on-demand billing). Deployed via `npx ampx sandbox --once`.
- **Verified by:** `aws kms get-public-key` against the deployed key, followed by `aws kms sign` (ECDSA_SHA_256, outside app code) on a test message, verified locally with `openssl dgst -verify` against the fetched public key — signature verified OK. Full identifiers in [[../Backend/Backend Index|Backend Index]].
- **Files changed:** `package.json`, `package-lock.json`, `amplify/backend.ts`, `amplify/auth/resource.ts`, `amplify/package.json`, `amplify/tsconfig.json` (deleted `amplify/data/resource.ts`), `amplify_outputs.json` (generated, gitignored), plus `docs/roster-vault/Backend/Backend Index.md` and `docs/roster-vault/Build and Deploy/Build and Deploy Index.md`.
- **Checkpoint saved:** 2026-09-09
- **Review Agent (self-run, since this touched a KMS key and its IAM surface):** Checked against the full checklist — key usage is sign/verify only (no decrypt path exists), private key never requested or logged, no `kms:*`/wildcard grants exist yet (none needed until Task 4's Lambda), no hardcoded region/account, no secrets committed. One flagged-and-accepted item: both the KMS key and table use `RemovalPolicy.DESTROY` (7-day pending window on the key) rather than `RETAIN`, since no device is enrolled yet — documented in Backend Index as a **must switch to RETAIN before any deploy with live enrolled devices**. Verdict: safe to proceed.

## Task 3: Flutter project scaffold and device identity
- **Status:** IN PROGRESS — implemented, real-device verification outstanding
- **Setup:** Task 2 complete (need the sandbox to enroll against later, though this task itself doesn't call it yet).
- **Work:** `flutter create` done — project `roster_vault` (org `com.rostervault`), targeting Android/iOS/Windows. Real home screen (`DeviceDebugScreen`, not the default counter demo). Nigel confirmed `biometric_signature` (researched and proposed below) — added to `pubspec.yaml` and implemented in `lib/services/device_identity_service.dart`: generates an ECDSA P-256 device keypair (alias `roster_vault_device_key`, `requireAuthentication: false`) and a random 16-byte `deviceId`, both created once and persisted (`flutter_secure_storage` for the deviceId; the plugin's own Keystore/Secure-Enclave storage for the keypair). Wired into `DeviceDebugScreen` to display both.
- **Correctness fix found during implementation:** the plugin's `createKeys` silently *replaces* an existing key under the same alias unless the caller checks first (`failIfExists` defaults to `false`). The service always calls `getKeyInfo` before `createKeys` for exactly this reason — documented in the service's doc comment and in [[../Security/Trust Anchors|Trust Anchors]].
- **Verify so far:** `flutter analyze` and `flutter test` both clean/passing. `flutter build windows --debug` succeeds. **Actually launched and screenshotted running** (screenshot sent to Nigel): shows "Roster Vault — Device Debug", a real `deviceId` (`920f031a5fa1edb1dd72a466aaedd396`), and a real public key in PEM format. **Relaunched and confirmed idempotent** — second launch showed the identical deviceId and public key, i.e. the key was reused, not regenerated. On the very first launch this took long enough (30s+) that it looked hung; added a 15-second timeout with a clear on-screen error message as a defensive improvement regardless (a real device screen should never spin silently forever), but the underlying cause turned out to be first-time TPM/Keystore provisioning latency, not a bug — every launch since has resolved in a few seconds. **Important caveat, confirmed not just theorized:** the returned public key is RSA-2048 SPKI (`MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...`), exactly matching the plugin's documented Windows-always-uses-RSA fallback — so this Windows run proves the UI/storage/idempotency wiring but genuinely cannot verify the ECDSA P-256 guarantee. That verification still needs an Android or iOS run. No Android emulator (AVD) exists on this machine yet (`flutter emulators` reports none) — creating one involves a sizeable system-image download, so held off pending Nigel's steer rather than done unattended.
- **Save:** Flutter project scaffold + device identity service exist; full verification pending Android/iOS run.
- **Depends on:** Task 2
- **Review Agent (self-run):** No API in `biometric_signature` ever returns a private key — only public keys and signatures are exposed to Dart, so there's no code path that could log/serialize one. `requireAuthentication: false` on the device key is intentional (Trust Anchor 2 isn't gated by a person's factor; Trust Anchor 3 in Task 6 will use the same plugin with it turned on, under a different alias). Verdict: safe to proceed; real-device signature-type verification is a test-coverage gap, not a safety flag.
- **Plugin research (resolved):** Flutter has no built-in hardware-backed asymmetric key generation. Nigel chose "vet a maintained plugin first," then confirmed the recommendation. Rejected candidates: `keystore_plugin` (supports it, but last published ~12 months ago, 1 like — under-maintained), `flutter_secp256r1` (pub.dev page 404s, couldn't verify), `biometric_crypto`/`synheart_auth` (not vetted in depth once a strong candidate emerged). **Chosen: `biometric_signature`** — verified publisher (visionflutter.com), actively maintained (v13, published 46 days prior), 160 pub points / 54 likes / 28.7k downloads, MIT license, supports multiple named keys via `keyAlias` (reusable for Task 6's per-user keys).

## Task 4: Enrollment flow, end to end (online)
- **Status:** NOT STARTED — scoped and sub-decomposed 2026-09-09, not yet approved to start
- **Setup:** Tasks 2 and 3 complete.
- **Scoping note (2026-09-09):** Task 4 alone crosses 5 layers (Flutter → Cognito → AppSync → Lambda → KMS → DynamoDB), adds new crypto wiring and new IAM surface, and has well over 3 acceptance criteria — too big for one sitting per the Story Agent's own rubric. Split into 4a/4b/4c below, mechanism before policy. **Scoping decision confirmed with Nigel:** Task 4c stores the enrollment token via `flutter_secure_storage`'s own OS-level encryption only — no PIN wrapping yet. The [[../Architecture/Enrollment Flow|Enrollment Flow]] diagram's steps 6–7 (PIN/biometric setup, PIN-wrapped encryption) are real but deferred to Task 6 as originally scoped in this checkpoint, not pulled forward — keeps Task 4 reviewable in one sitting and separates mechanism from policy.

### Task 4a: Enrollment Lambda + AppSync mutation (backend only, no UI)
- **Status:** COMPLETE
- **Work:** Added `amplify/appsync/schema.graphql` (single `enroll` mutation, Cognito User Pool-authorized) and `amplify/functions/enroll/{resource.ts,handler.ts}`. Handler reads any existing `DeviceEnrollments` row (preserving epoch across re-enrollment), writes `{deviceId, userId, devicePubKey, userPubKey, epoch, status: active, lastIssuedExpiry}`, hand-builds a standard ES256 JWS (`{user_id, device_id, scopes: [offline_signin], epoch, iat, exp}` at ~48h TTL) signed via `kms:Sign`, converting KMS's DER signature to JWS's raw 64-byte R‖S format. Baked the issuer's public key into the app as `lib/services/issuer_public_key.dart` (checked in, with its own regeneration command). Full detail in [[../Backend/Backend Index|Backend Index]].
- **Verify:** Created a real Cognito test user (`test-task4a@rostervault.dev`), obtained a real ID token (`admin-initiate-auth`), called `enroll` over HTTPS against the deployed sandbox AppSync endpoint, got back a signed JWT, and verified its signature locally in Node (`crypto.verify` with `dsaEncoding: 'ieee-p1363'`, against the exact PEM baked into the app) — **signature valid**, 64-byte raw signature as expected for P-256, correct claim shape. Confirmed via direct `GetItem` that the `DeviceEnrollments` row was written correctly. Re-called `enroll` a second time after tightening the DynamoDB grant (see Review Agent below) — still works, and `epoch` stayed `0` across both calls, confirming the read-preserves-epoch logic. No Flutter UI involved, as scoped.
- **Save:** Enrollment Lambda deployed to sandbox, callable, producing verifiably-signed tokens.
- **Files changed:** `amplify/appsync/schema.graphql` (new), `amplify/functions/enroll/resource.ts` (new), `amplify/functions/enroll/handler.ts` (new), `amplify/backend.ts`, `lib/services/issuer_public_key.dart` (new), `test/widget_test.dart` (unrelated pre-existing bug fixed, see Plan Changes Log), `package.json`/`package-lock.json` (added `@aws-sdk/client-dynamodb`, `@aws-sdk/util-dynamodb`, `@types/node`), `docs/roster-vault/Backend/Backend Index.md`, `docs/roster-vault/Security/Trust Anchors.md`.
- **Depends on:** Task 2.
- **Review Agent (self-run, full checklist against `amplify/backend.ts`, `amplify/functions/enroll/*`, `amplify/appsync/schema.graphql`):**
  - ✅ Key material never leaves its boundary — handler only ever calls `kms:Sign` (never a private-key-export API); the token returned to the caller is the intended deliverable, not leaked secret material; no logging of tokens/keys in the handler.
  - ✅ Token/epoch correctness (issuance side) — epoch is read-then-preserved, never reset by self-re-enrollment; only an explicit admin action (Task 8) will ever bump it.
  - ✅ Environment leakage — no dev/test values hardcoded in Lambda code; the CLI test user/password used for verification live only in shell history and gitignored `.artifacts/`, never committed.
  - ✅ Missing environment variables — `ISSUER_SIGNING_KEY_ID` and `DEVICE_ENROLLMENTS_TABLE_NAME` both set and both documented in Backend Index.
  - ✅ Cross-account/region — no hardcoded region or account id introduced; `KMSClient({})`/`DynamoDBClient({})` pick up the Lambda's own execution region.
  - ✅ Secrets and credentials — no secrets committed; KMS key ARN/id treated as identifiers, not secrets (consistent with Task 2's own precedent).
  - ⚠️ **IAM scope creep, found and fixed:** initial implementation used `deviceEnrollments.grantReadWriteData(enrollFn)`, which grants `Query`/`Scan`/`DeleteItem`/`BatchWriteItem`/`BatchGetItem` the handler never calls. Tightened to `deviceEnrollments.grant(enrollFn, 'dynamodb:GetItem', 'dynamodb:PutItem')` — exactly what's used. Redeployed and re-verified working after the fix.
  - ⚠️ **Task 4a's own stated scope not fully done on first pass, found and fixed:** the issuer public key had been fetched ad hoc for CLI verification but not actually baked into the app as originally scoped. Added `lib/services/issuer_public_key.dart` before considering the task complete.
  - **Verdict:** safe to proceed, both flagged items resolved before this commit (not merely noted-and-deferred).
- **Checkpoint saved:** 2026-09-09

### Task 4a note: unrelated pre-existing test bug found and fixed
`flutter test` failed (`A Timer is still pending even after the widget tree was disposed`) before any Task 4a work touched `main.dart` or the test — `DeviceDebugScreen.initState`'s 15-second timeout (Task 3) creates a real `Timer` that a widget test's single `pumpWidget` never advances past, since there's no real platform channel behind `biometric_signature` in a test environment for the underlying future to resolve against. `testWidgets` already runs inside a fake-async zone, so `test/widget_test.dart` now pumps an extra 16 seconds after its assertions to let that timer fire before the test ends, rather than leaving a stray pending timer. Not part of Task 4a's own scope, but left broken would have violated the Story Agent's "task must end in a stable state" rule — fixed rather than left red. This means Task 3's "flutter test... passing" claim was stale/inaccurate at the time it was written; corrected here.

### Task 4b: Flutter Cognito login screen
- **Work:** Add `amplify_flutter` + `amplify_auth_cognito`, initialize Amplify in `main.dart`, build a real sign-up/sign-in screen against the deployed User Pool (`ap-southeast-2_B1k3XjP8l`).
- **Verify:** A real person signs up/in on screen against the actual Cognito pool; the screen shows an authenticated state.
- **Save:** Working login screen, authenticated session obtainable.
- **Depends on:** Task 2. (Independent of 4a — order between 4a/4b doesn't matter; both must land before 4c.)

### Task 4c: Wire it end to end + local storage of the result
- **Work:** Generate a per-user keypair, generalizing Task 3's `device_identity_service` pattern to a parameterized key alias (Trust Anchor 3). Call `enroll` with both pubkeys + the ID token from 4b, receive the signed token, store it via `flutter_secure_storage` (placeholder encryption — see scoping decision above), add a debug view showing decoded claims and a live signature check against the bundled public key.
- **Verify:** **Second on-screen milestone** (unchanged from original Task 4 verify): a real person taps through login, signs in online, and watches enrollment complete — the app shows a valid, correctly-signed offline token stored locally (inspectable in a debug view). Confirmed against the deployed sandbox, not mocked.
- **Save:** One real enrolled profile exists on a test device.
- **Depends on:** Task 4a, Task 4b, Task 3.

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
- **2026-09-09:** Task 4 sub-decomposed into 4a (Enrollment Lambda + AppSync mutation, backend-only), 4b (Flutter Cognito login screen), 4c (wire end to end + local storage of the token) — too big for one sitting as a single task per the Story Agent's own complexity rubric. Confirmed with Nigel: Task 4c uses placeholder (`flutter_secure_storage`-only) local storage, not pulling Task 6's PIN/Argon2id wrapping forward. Not yet approved to start execution.
- **2026-09-09 (autonomous mode begins):** Nigel explicitly authorized continuing through Task 4a onward (4b, 4c, then 5–10) without pausing for live checkpoints — he's stepping away and will review this file in one sitting. Directive: pick recommended/lowest-risk defaults at Story Agent Phase-3 decision points instead of waiting, log every such decision here, keep this file rigorously accurate as the substitute for the live review. Guardrails that stayed in force throughout: stay confined to this repo's own Amplify backend; never touch the sibling `where_in_nz_v3` project or the pre-existing unrelated `roster-app` (appId `d2wnajnfhijfg7`) sharing this AWS account (re-confirmed via `aws amplify list-apps` before any AWS write this session — same three apps as Task 1's incident log, nothing added or removed); no `git push`, no PR, local commits only; no destructive/irreversible action beyond what's already agreed (sandbox `RemovalPolicy.DESTROY` posture, no force-push, no history rewriting). Partway through Task 4a, Nigel further relaxed two of the original stop conditions: (1) "no obvious recommended default" is no longer a hard stop — just make the call and log it (this and all entries below reflect that); (2) missing Android emulator/device is no longer a hard stop for the *whole* run — document the gap honestly, skip only the specific sub-step that needs it, keep going on everything else.
- **2026-09-09 (Task 4a, autonomous):** Confirmed via `aws sts get-caller-identity` + `aws amplify list-apps` before any write — same account (445567075330), same three apps as Task 1's incident log (`roster-vault` ours, `where_in_nz_v3` and `roster-app` untouched). `flutter emulators --create` attempted once as instructed; failed with no Android AVD system images available (a sizeable download, consistent with Task 3's existing note) — not pursued further per the relaxed device stop condition; Task 3's outstanding P-256 verification and any later device-dependent milestones remain genuinely blocked on Nigel providing hardware or approving the system-image download, not faked.
- **2026-09-09 (Task 4a, autonomous):** Circular nested-stack dependency between the enrollment function's default stack and the manually-created `RosterVaultCore` stack (CloudFormation rejected it outright — not a style choice, a hard deploy failure). Fixed by moving the function into `RosterVaultCore` via `resourceGroupName` and obtaining that stack via `backend.enroll.stack` instead of a second `createStack` call. Side effect: the `DeviceEnrollments` table and the KMS key's *alias* (not the underlying CMK — same key id `fdf9ab21-...` throughout, confirmed in `amplify_outputs.json` after redeploy) were recreated as new physical resources during the stack restructuring. Acceptable under the already-agreed sandbox `RemovalPolicy.DESTROY` posture (no live enrolled devices exist yet); `docs/roster-vault/Backend/Backend Index.md` updated to stop hardcoding the table name, since it now changes with stack topology.
- **2026-09-09 (Task 4a, autonomous, Review Agent self-check):** Two items found and fixed before commit, not just noted: (1) `grantReadWriteData()` was broader than the handler's actual `GetItem`+`PutItem` usage — tightened to exactly those two actions; (2) the issuer public key had been fetched for CLI verification but not actually baked into the app as Task 4a's own scope required — added `lib/services/issuer_public_key.dart` before treating the task as done. Full detail under Task 4a above.
- **2026-09-09 (Task 4a, autonomous):** Added `ALLOW_ADMIN_USER_PASSWORD_AUTH` to the Cognito app client's explicit auth flows so this project's own AWS-credentialed tooling could obtain a real ID token for CLI verification without hand-implementing SRP. Deliberately not the broader `ALLOW_USER_PASSWORD_AUTH` (would expose direct password auth to any client holding the app client id) — `admin-initiate-auth` requires the caller to already hold AWS IAM credentials, a narrower and more defensible surface. The one end-user-facing flow, SRP, is unchanged. Judgment call under the relaxed decision-point rule; reasoning recorded here and in Backend Index.
- **2026-09-09 (Task 4a, autonomous):** Simplified the enrollment response to `{token, epoch, expiresAt}` rather than the architecture diagram's "token + device certificate" — no concrete shape for a "device certificate" exists anywhere in the docs, and inventing one without further spec would be guessing at a security-relevant design detail rather than a low-stakes default. Flagged here rather than silently dropped; worth Nigel's explicit input on whether a device certificate is actually needed and what it should contain, before Task 8 (revocation) potentially needs it.
- **2026-09-09 (Task 4a, autonomous):** Found and fixed a pre-existing, unrelated test failure (`flutter test` — pending Timer from Task 3's 15s device-keygen timeout, never advanced past in the widget test). Not part of Task 4a's own diff, but left broken it would have violated "every task ends in a stable state" for whatever task ran next. See the dedicated note under Task 4a above; this also means Task 3's checkpoint's "flutter test... passing" claim was inaccurate at the time and should be read as corrected here.

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
