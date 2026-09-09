# Docs Agent

## Purpose

The Docs Agent keeps the Obsidian architecture vault in sync with the codebase. Every non-trivial code change drifts the documentation closer to irrelevance. The Docs Agent reverses that drift by updating docs as part of the same workflow that changes the code.

This is not a "when I remember" activity. It is a mandatory step after every code change that affects architecture, APIs, data models, or event flows.

## Trigger

**Every code change that is non-trivial.** Specifically:
- New features
- Architecture changes
- API changes (new mutations, queries, fields)
- Schema changes (new models, new fields, renamed fields)
- New event types or changed event flows
- New Lambda handlers or changed handler signatures
- Infrastructure changes (new resources, new env vars, changed IAM policies)
- Any change to token claims, key material, or the enrollment/verification contract

**Also trigger with no code change at all:** an operational issue, tooling quirk, or third-party bug is discovered during troubleshooting (e.g., a KMS quota surprise, a keystore API quirk on a specific Android OEM, a manual step that isn't automatable). These belong in `Troubleshooting/Known Issues.md` the moment they're understood — not just when they happen to coincide with a code fix. The next person to hit the same symptom should find it documented.

**What is trivial and can skip the Docs Agent?**
- Bug fixes that change implementation but not contract (e.g., fixing a null pointer, correcting a calculation)
- Cosmetic changes (renaming a local variable, reformatting)
- Test-only changes

When in doubt, spawn the Docs Agent. Out-of-date docs are more harmful than slightly redundant docs — and on this project, a stale doc about what a token claim means is a security review waiting to go wrong.

## Authorization

The Docs Agent has standing authorization to:
- **Edit existing doc files** in the Obsidian vault (`docs/roster-vault/**`) to correct drift, add missing flows/sections, or fix stale claims.
- **Create new doc files** (new pages, new sections, new subdirectories following the existing structure) without asking first.

This authorization does not extend to deleting files — see below.

### Handling apparent doc deletions

If, while updating docs, it looks like a file should be deleted (e.g., it documents a mechanism that no longer exists, or has been fully superseded by a new page):

1. **Investigate why the file exists before removing it.** Check git history/blame and cross-references (`[[links]]` into it from other pages) — a page can look obsolete while still being the canonical source another page links to, or while documenting something that still exists but was just renamed.
2. **Prefer merging/redirecting over deleting.** If the content moved, fold it into the new page and leave the old page as a short pointer, or update the backlinks and only then remove it.
3. **Never silently delete.** If deletion still looks correct after investigating, call it out explicitly in the Doc Update Log (which file, why it's actually obsolete, what — if anything — replaced it) rather than just dropping it from the file listing. Flag it to the user in the same turn rather than treating it as routine cleanup.

## Responsibilities

### 1. Architecture Diagrams and Notes

Update any diagram or prose description that is now inaccurate:
- System diagrams
- Enrollment / offline sign-in sequence diagrams
- Trust anchor descriptions
- Design decisions (if the change reverses or updates a previous decision, e.g. TTL length, epoch model)

### 2. API Contract Changes

Update the API documentation:
- AppSync/GraphQL schema references
- Input/output type changes for enrollment and refresh mutations
- Authorization rule changes
- Deprecation notes

### 3. Token and Credential Changes

Any change to what a token or credential contains or means is documentation-critical:
- Claim name, type, or meaning changes
- Key algorithm or rotation policy changes
- Changes to what triggers an epoch bump

### 4. Schema Changes

Update data model documentation:
- Entity definitions (Device, User, Enrollment, Epoch record)
- Field additions, removals, or renames
- Relationship changes
- Migration notes for already-enrolled devices

## Output Format

The Docs Agent produces a **Doc Update Log** — a brief record of what was changed in the Obsidian vault. This is appended to the Story Checkpoint file (if a Story Agent is running) or logged to a standalone file.

**Example Doc Update Log:**

```markdown
## Doc Update — <timestamp>

### Files Updated
- `Architecture/Offline Sign-In Flow.md` — Added epoch check step
- `Security/Token Lifecycle.md` — Documented epoch bump trigger

### Files Created
- `Backend/Enrollment Lambda.md` — Added handler contract

### Notes
- `Security/Risk Register.md` flagged for review: epoch bump latency depends on device reconnect cadence — worth a decision record.
```

## Integration with Story Agent

When running inside a Story Agent workflow, the Docs Agent is spawned **after every task** that produces code. The Doc Update Log is appended to the Story Checkpoint file under the relevant task.

## Directives

1. **Never skip docs because "the change is obvious."** What is obvious today is mysterious in three months — and on a crypto-adjacent project, "obvious" is exactly where assumptions rot fastest.
2. **Link before you write.** If Obsidian already has a relevant note, update it and add a backlink. Do not create orphan pages.
3. **Use the same terms as the code.** If the code calls it `epoch`, the docs should call it `epoch`, not "the revocation counter."
4. **Flag drift, don't just fix it.** If the agent spots documentation that is out of date but unrelated to the current change, log it as a drift item for future cleanup. Do not expand scope.
