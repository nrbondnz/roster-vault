# Build and Deploy Index

## Local Sandbox (Task 2, done)

`npx ampx sandbox` deploys straight from the developer's own AWS credentials — no git provider involved. This is how the Amplify Gen 2 skeleton (Cognito, KMS issuer key, `DeviceEnrollments` table) got deployed for the first time; see [[../Backend/Backend Index|Backend Index]] for the actual identifiers. Good for solo local iteration; not how a team or CI builds this project.

Command used: `npx ampx sandbox --once` (single deploy-and-exit, rather than the default watch mode, since this was run unattended).

## Amplify Hosting / Git Connection (Task 1, in progress)

Amplify's hosted backend build pipeline is a separate mechanism from the sandbox above — it builds from a connected git repository (GitHub/GitLab/Bitbucket/CodeCommit) on push, which is what lets a team (not just one developer's local credentials) get a backend build. See Task 1 in [[../stories/story-checkpoint-mvp|Story Checkpoint: MVP]] — inserted specifically because the original plan jumped straight to the sandbox and missed this.

- **Repo:** `https://github.com/nrbondnz/roster-vault` (private), `main` branch. Initial commit pushed 2026-09-09.
- **Amplify Hosting app:** not yet created — Nigel is connecting the repo in the AWS Amplify Console himself.

Expected notes once that lands:
- Amplify Hosting app ID
- What triggers a build (push to `main`? PR previews?)

## Still To Come

- KMS key rotation procedure
- CI/CD beyond Amplify Hosting's own build, if this project ever needs one

## See Also

- [[../Index|Vault Index]]
- [[../Backend/Backend Index|Backend Index]]
- [[../Backend/Tech Stack Mapping|Tech Stack Mapping]]
