# Backend Index

## In This Folder

- [[Tech Stack Mapping]] — every abstract requirement, mapped to a real AWS Amplify Gen 2 service or Flutter package
- Data model notes (Device, User Enrollment, Epoch record) — sketched in [[Tech Stack Mapping]]; the `enroll` mutation (Task 4a) now actually writes to the table

## Deployed Sandbox (Task 2, extended by Task 4a)

The Amplify Gen 2 skeleton — Cognito User Pool, the KMS issuer signing key, the `DeviceEnrollments` table, and (as of Task 4a) the enrollment AppSync API + Lambda — is deployed to a local dev sandbox, not yet to any hosted environment (that lands with Task 1's Amplify Hosting git connection).

| Resource | Identifier |
|---|---|
| Sandbox stack | `amplify-appmanagement-nigel-sandbox-9e985e1221` |
| Region | `ap-southeast-2` |
| Issuer signing key ARN | `arn:aws:kms:ap-southeast-2:445567075330:key/fdf9ab21-2884-4a88-9e1c-1b10a3d8f103` (alias `alias/roster-vault-issuer-signing-key-*`, unchanged since Task 2) |
| `DeviceEnrollments` table | physically recreated during Task 4a's stack restructuring (see Plan Changes Log in the story checkpoint) — current name in `amplify_outputs.json` → `custom.deviceEnrollmentsTableName`, not hardcoded here since it changes on every stack topology change |
| Cognito User Pool | `ap-southeast-2_B1k3XjP8l` |
| Cognito App Client | `iivdcp31pfelnbujd8p8anofu` |
| Enrollment AppSync API | name `roster-vault-enrollment-api`; URL/id in `amplify_outputs.json` → `custom.enrollApiUrl` / `custom.enrollApiId` |
| Enrollment Lambda | `RosterVaultCore/enroll-lambda`, env vars `ISSUER_SIGNING_KEY_ID`, `DEVICE_ENROLLMENTS_TABLE_NAME` |

Defined in `amplify/backend.ts` (Cognito via `defineAuth` in `amplify/auth/resource.ts`; KMS key, DynamoDB table, AppSync API, and the enrollment Lambda all placed in the **same** nested `RosterVaultCore` stack — see Task 4a's circular-dependency note below — since they're consumed by a custom Lambda resolver rather than Amplify's `data` construct).

**Note on removal policy:** the KMS key and the table are currently `RemovalPolicy.DESTROY` (key has a 7-day pending deletion window) since no device is enrolled against them yet. This must switch to `RETAIN` before any deploy that has live enrolled devices depending on the issuer key — see the Review Agent's rollback-safety checklist in [[../../agents/review-agent/review-agent|Review Agent]].

## Task 4a: Enrollment API

Single custom mutation, not modeled through Amplify's `data` construct. Schema: `amplify/appsync/schema.graphql`. Resolver: `amplify/functions/enroll/handler.ts` (Lambda, Node, AWS SDK v3 `@aws-sdk/client-kms` + `@aws-sdk/client-dynamodb`).

- **Auth:** AppSync's own Cognito User Pool authorizer verifies the caller's ID token before the resolver runs; the handler trusts `event.identity.sub` as already-verified.
- **Token construction:** hand-built JWS (ES256), not a library — `header.payload` signed via `kms:Sign` (`SigningAlgorithm: ECDSA_SHA_256`, `MessageType: RAW`). KMS returns a DER-encoded signature; JWS ES256 requires the raw 64-byte `R‖S` concatenation, so the handler does that DER→raw conversion itself (the one genuinely non-obvious piece of wire-format code in the handler).
- **Epoch handling:** the handler reads any existing `DeviceEnrollments` row first and carries its `epoch` forward — re-enrollment never resets it. Epoch is only ever bumped by an explicit admin action (Task 8).
- **Grants:** `kms:Sign` only (never `Decrypt` — the key is `SIGN_VERIFY`-only) and exactly `dynamodb:GetItem` + `dynamodb:PutItem` on the table (not the broader `grantReadWriteData()` helper, which would also hand out `Query`/`Scan`/`DeleteItem`/`BatchWriteItem` the handler never calls — tightened during the Task 4a Review Agent self-check).
- **Scope note:** the architecture doc's enrollment sequence diagram mentions the enrollment call returning "token + device certificate." Only `{token, epoch, expiresAt}` is implemented — no concrete shape for a "device certificate" exists anywhere else in the docs, and inventing one without further spec would be scope creep. Flagged, not silently dropped.

### Non-obvious deployment issues hit and fixed (Task 4a)

1. **Circular nested-stack dependency.** Originally the function was left in Amplify's default `function` stack while KMS/table/AppSync lived in a separately-created `RosterVaultCore` stack. Granting the function access to those resources (needed for signing/writes) made the function's stack depend on `RosterVaultCore`; wiring the function as an AppSync Lambda data source made `RosterVaultCore` depend back on the function's stack. CloudFormation rejects the cycle outright. **Fix:** set `resourceGroupName: 'RosterVaultCore'` in `amplify/functions/enroll/resource.ts` so the function lives in the *same* nested stack as everything it touches, and obtain that stack via `backend.enroll.stack` in `backend.ts` rather than a separate `backend.createStack('RosterVaultCore')` call (calling both throws "Custom stack named RosterVaultCore has already been created").
2. **AppSync API name length.** `appsync.GraphqlApi`'s `name` has a 100-char cap; suffixing it with the full nested-stack name (as the existing KMS alias pattern does, since KMS aliases allow far more) blew past that. AppSync API names don't need global uniqueness (that's what `apiId` is for), so no suffix is needed.
3. **A stray, broken `amplify/node_modules`.** A partially-installed nested `node_modules` under `amplify/` (gitignored, untracked) shadowed the correctly-installed root one and broke `@aws-amplify/backend` resolution with a confusing "cannot find package" error. Deleting it (safe — it's a regenerable, untracked build artifact) fixed it immediately.

## Cognito Auth Flows

`ALLOW_ADMIN_USER_PASSWORD_AUTH` was added to the app client's `ExplicitAuthFlows` (originally just SRP + custom + refresh) so this project's own AWS-credentialed CLI/backend tooling can obtain a real ID token for testing (`aws cognito-idp admin-initiate-auth`) without implementing SRP by hand. Deliberately **not** `ALLOW_USER_PASSWORD_AUTH`, which would expose direct password auth to any client holding the app client id — `admin-initiate-auth` requires the caller to already hold AWS IAM credentials with `cognito-idp:AdminInitiateAuth`, a materially narrower surface. The only end-user-facing flow remains `ALLOW_USER_SRP_AUTH` (used by Task 4b's real login screen), unchanged.

## See Also

- [[../Index|Vault Index]]
- [[../Architecture/Architecture Index|Architecture Index]]
- [[../Build and Deploy/Build and Deploy Index|Build and Deploy Index]]
