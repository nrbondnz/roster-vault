# Roster Vault Documentation

Welcome to the Obsidian knowledge base for **Roster Vault** — a Flutter application, backed by AWS Amplify Gen 2, that solves one narrow and genuinely uncommon requirement: **authenticating multiple people on a single shared, unmanaged device, with no live connection to an identity provider at sign-in time.**

This vault is organised by domain. Use the folder indices below to navigate, or follow wiki-links (`[[Like This]]`) between related notes.

---

## The Requirement, in One Paragraph

Standard SSO/OIDC assumes one user, one device, one live round trip to an identity provider at sign-in. This project needs the opposite on all three counts: several people sharing one phone or tablet, verified while the device has no signal at all, on hardware with no MDM enrollment or OS-level device management to lean on. See [[The Actual Requirement]] for the full restatement and why the obvious answer doesn't fit.

---

## Folder Map

| Folder | What's Inside |
|--------|---------------|
| [[Management Index\|Management]] | Project overview, glossary, how this vault carries forward practice from `where_in_nz_v3` |
| [[Architecture Index\|Architecture]] | System diagram, enrollment flow, offline sign-in flow, multi-user partitioning |
| [[Security Index\|Security]] | Trust anchors, token lifecycle, epoch/revocation model, risk register |
| [[Backend Index\|Backend]] | Amplify Gen 2 services, the concrete AWS-to-requirement mapping |
| [[Frontend Index\|Frontend]] | Flutter app structure, roster UI, local verification module |
| [[Build and Deploy Index\|Build and Deploy]] | Amplify Gen 2 setup, environments, CI/CD (to be filled in as Phase 0 lands) |
| [[Operations Index\|Operations]] | Runbooks, monitoring, key rotation procedure (to be filled in) |
| [[Troubleshooting Index\|Troubleshooting]] | Known issues, error catalog, quick fixes |

---

## Quick Links

- [[The Actual Requirement]] — restated precisely, and why OIDC/SSO alone doesn't solve it
- [[Trust Anchors]] — the three pieces of key material the whole system rests on
- [[Enrollment Flow]] — the one online step that makes every later offline sign-in possible
- [[Offline Sign-In Flow]] — the flow that has to work with the network off
- [[Token Lifecycle and Revocation]] — TTLs, epochs, and what "revoked" actually means offline
- [[Tech Stack Mapping]] — every abstract piece, mapped to a real AWS service or Flutter package
- [[Risk Register]] — what to say out loud to the client before they discover it themselves
- [[story-checkpoint-mvp|Story Checkpoint: MVP]] — the build plan we're actually following, task by task

---

## Working Discipline

This project inherits the agent-driven workflow from `where_in_nz_v3` — see [[../agents/index|Agents Index]]. In short: big features get decomposed by the Story Agent into demonstrable, checkpointed tasks; every code change updates this vault and gets tests; anything touching KMS, IAM, or local key storage gets a safety review before it's committed. Given what this project actually does, that last one is not a formality.
