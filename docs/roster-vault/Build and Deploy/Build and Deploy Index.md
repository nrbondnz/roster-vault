# Build and Deploy Index

## Local Sandbox (Task 2, done)

`npx ampx sandbox` deploys straight from the developer's own AWS credentials — no git provider involved. This is how the Amplify Gen 2 skeleton (Cognito, KMS issuer key, `DeviceEnrollments` table) got deployed for the first time; see [[../Backend/Backend Index|Backend Index]] for the actual identifiers. Good for solo local iteration; not how a team or CI builds this project.

Command used: `npx ampx sandbox --once` (single deploy-and-exit, rather than the default watch mode, since this was run unattended).

## Amplify Hosting / Git Connection (Task 1)

Amplify's hosted backend build pipeline is a separate mechanism from the sandbox above — it builds from a connected git repository (GitHub/GitLab/Bitbucket/CodeCommit) on push, which is what lets a team (not just one developer's local credentials) get a backend build. See Task 1 in [[../stories/story-checkpoint-mvp|Story Checkpoint: MVP]] — inserted specifically because the original plan jumped straight to the sandbox and missed this.

- **Repo:** `https://github.com/nrbondnz/roster-vault` (private), `main` branch.
- **Amplify Hosting app:** `roster-vault`, appId `d1263eo28hwyl9`, `ap-southeast-2`, default domain `d1263eo28hwyl9.amplifyapp.com`.
- **Backend deploy IAM role:** `arn:aws:iam::445567075330:role/amplify-roster-vault-backend-role` — trusted only by `amplify.amazonaws.com`, with AWS's `AmplifyBackendDeployFullAccess` managed policy. Created specifically for this app; does not touch the pre-existing `where_in_nz_v3` or `roster-app` apps' roles in the same AWS account.
- **This account is shared.** It also hosts `where_in_nz_v3` and an older, unrelated `roster-app` (appId `d2wnajnfhijfg7`, staff/admin-group invite system, predates this project) — neither was touched while setting this up.
- **Build spec (`amplify.yml`, repo root):** backend-only. Runs `npm install` (not `npm ci` — see note below) then `npx ampx pipeline-deploy`. The "frontend" phase just publishes a placeholder `index.html`, since Amplify Hosting requires every branch to publish *something*, but this repo's real frontend is the Flutter app, which Amplify Hosting doesn't build or serve.
- **`npm ci` vs `npm install`:** `npm ci` fails intermittently on this project's `package-lock.json`, each time reporting a *different* package "missing from lock file" (seen: `@opentelemetry/core@2.0.0`, then `@aws-cdk/toolkit-lib@1.19.0` + others) — reproduced locally, survives a full lockfile regeneration. This is a known class of npm bug around `aws-cdk-lib`'s own optional dependency subtree, not a mistake in this repo's dependencies. `amplify.yml` uses `npm install` instead, which is idempotent and reliable here.
- **Setup note:** two empty duplicate `roster-vault` Amplify apps were created and then deleted during setup — artifacts of `aws amplify create-app` calls that were blocked by Claude Code's auto-mode permission classifier but apparently still reached the AWS API before the block took effect. Worth knowing: a "blocked by classifier" result is not reliable proof that zero side effects occurred against AWS.

What triggers a build: a push to `main` (the branch was created with `enableAutoBuild: true`, and Amplify auto-created a GitHub webhook + deploy key during app creation).

## Still To Come

- KMS key rotation procedure
- CI/CD beyond Amplify Hosting's own build, if this project ever needs one

## See Also

- [[../Index|Vault Index]]
- [[../Backend/Backend Index|Backend Index]]
- [[../Backend/Tech Stack Mapping|Tech Stack Mapping]]
