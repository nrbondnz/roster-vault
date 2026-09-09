# Backend Index

## In This Folder

- [[Tech Stack Mapping]] — every abstract requirement, mapped to a real AWS Amplify Gen 2 service or Flutter package
- Data model notes (Device, User Enrollment, Epoch record) — sketched in [[Tech Stack Mapping]]; formalised further once the enrollment Lambda (Task 4) actually writes to the table

## Deployed Sandbox (Task 2)

The Amplify Gen 2 skeleton — Cognito User Pool, the KMS issuer signing key, and the `DeviceEnrollments` table — is deployed to a local dev sandbox, not yet to any hosted environment (that lands with Task 1's Amplify Hosting git connection).

| Resource | Identifier |
|---|---|
| Sandbox stack | `amplify-appmanagement-nigel-sandbox-9e985e1221` |
| Region | `ap-southeast-2` |
| Issuer signing key ARN | `arn:aws:kms:ap-southeast-2:445567075330:key/fdf9ab21-2884-4a88-9e1c-1b10a3d8f103` (alias `alias/roster-vault-issuer-signing-key`) |
| `DeviceEnrollments` table | `DeviceEnrollments` (DynamoDB, on-demand billing) |
| Cognito User Pool | `ap-southeast-2_B1k3XjP8l` |

Defined in `amplify/backend.ts` (Cognito via `defineAuth` in `amplify/auth/resource.ts`; KMS key and DynamoDB table as raw CDK constructs in a nested `RosterVaultCore` stack, since they're consumed by a future custom Lambda resolver rather than Amplify's `data` construct).

**Note on removal policy:** both the KMS key and the table are currently `RemovalPolicy.DESTROY` (key has a 7-day pending deletion window) since no device is enrolled against them yet. This must switch to `RETAIN` before any deploy that has live enrolled devices depending on the issuer key — see the Review Agent's rollback-safety checklist in [[../../agents/review-agent/review-agent|Review Agent]].

## See Also

- [[../Index|Vault Index]]
- [[../Architecture/Architecture Index|Architecture Index]]
- [[../Build and Deploy/Build and Deploy Index|Build and Deploy Index]]
