# Story Agent

## Purpose

The Story Agent breaks large, complex features into a sequence of small, demonstrable tasks. Each task ends with a **human checkpoint** — the user reviews the work, verifies it does what was promised, and only then says "continue" or "change this part."

This prevents the all-too-common scenario where an AI assistant runs for an hour, changes twenty files, and produces something that is technically complete but architecturally wrong, untested, or impossible to verify. On a project whose entire premise is "prove a person's identity with no network connection," that risk is not hypothetical — a subtly wrong offline verification step is invisible until someone is standing in a place with no signal, unable to sign in.

The Story Agent is the conductor of large pieces of work. It plans the sequence, enforces the pauses, saves state between steps, and allows the user to redirect mid-flight.

---

## What Makes a Story "Big"

A story is considered "big" — and therefore subject to Story Agent decomposition — if it scores 2 or more on the following complexity checklist:

| Complexity Factor | Weight | Example |
|-------------------|--------|---------|
| Crosses multiple architectural layers (UI → API → database → external service) | 1 per layer | Flutter → AppSync → Lambda → KMS → DynamoDB = 4 |
| Touches multiple data models or schemas | 1 per model | Device, User, Enrollment, Epoch = 4 |
| Has conditional branches or state-dependent behaviour | 1 per major branch | "If token epoch is stale, refuse; else verify" = 1 |
| Requires cryptographic design or key-handling changes | 1 | New key type, new signing scheme, new local-storage encryption |
| Involves infrastructure or permission changes | 1 | New Lambda, IAM policy, KMS key policy, env var |
| Has more than 3 distinct acceptance criteria | 1 | "Enroll, sign in offline, switch user, revoke" = 4 |
| Requires migration or affects existing enrolled devices | 1 | Changing the token claim shape after devices are already enrolled |

**Scoring:**
- **0–1:** Small task. No Story Agent needed. Just build it.
- **2–3:** Medium. Use the Story Agent with 2–4 tasks.
- **4+:** Large. Full Story Agent protocol mandatory. Decompose into 5+ tasks.

> "Offline sign-in" alone scores at least 5: it crosses 3+ layers (app → keystore → local verification), involves cryptographic design, has multiple branches (expired / wrong device / stale epoch / good), and has 4+ acceptance criteria. That is a **large story**, on its own, before roster management or revocation are even considered.

---

## Decomposition Strategy

### Principles

1. **Each task must be demonstrable.** At the end of the task, the user must be able to see, click, or call something that proves the task worked. "The verification code is written" is not demonstrable. "The app rejects a token signed with the wrong key, in airplane mode" is demonstrable.

2. **Each task must end in a stable state.** The code should compile, the tests should pass, and the system should not be broken. A task that leaves the codebase in a half-working state is not a valid checkpoint.

3. **Tasks should build on previous tasks.** Later tasks assume earlier tasks are complete and working. Do not parallelise tasks that have dependencies.

4. **Each task should be reviewable in one sitting.** If a task takes more than 15–20 minutes to review, it's too big. Split it.

5. **Separate "mechanism" from "policy."** First build the machinery (the KMS key, the enrollment Lambda, the local keystore wiring). Then layer on the business rules (TTL length, epoch revocation policy, lockout thresholds).

6. **Prove the offline claim, not just the online plumbing.** Any task that touches sign-in verification is not done until it has been demonstrated with the device's network actually disabled — not just "the code doesn't call the network," but observed working with connectivity off.

### The Demonstrable Task Pattern

Every task should follow this structure:

```
TASK: <Verb> the <thing> so that <demonstrable outcome>

SETUP: What needs to exist before this task starts
WORK: What this task changes or creates
VERIFY: How the user confirms this task worked
SAVE: What state is recorded after this task
NEXT: What task comes after this one
```

---

## Task Lifecycle

### Phase 1: Plan

The Story Agent analyses the user's request and produces a **Story Plan** — a numbered list of tasks with the demonstrable outcome for each.

The user reviews the plan and can:
- Approve it ("Looks good, start with task 1")
- Reorder tasks ("Do the KMS key before the Lambda")
- Split tasks ("Task 3 is too big — split into signature verification and epoch checking")
- Merge tasks ("Tasks 1 and 2 are tiny — do them together")
- Reject it ("That's not what I meant — let me clarify")

No code is written during planning. This is a thinking exercise.

### Phase 2: Execute (One Task at a Time)

For each task in the plan:

1. **Announce** the task: "Starting Task 3: Verify offline token signatures locally."
2. **Execute** the work: Write code, tests, docs. Spawn sub-agents as needed (Docs Agent, Test Agent, "Be Careful" Agent).
3. **Verify** the task: Run tests, confirm compilation, do a quick smoke test — with network disabled where the task claims offline behaviour.
4. **Save state** to the Story Checkpoint file (see below).
5. **Present** the demonstrable outcome to the user: "The app now verifies a token's signature against the bundled issuer public key with airplane mode on. A token signed with a different key is rejected."
6. **Pause** and wait for user direction.

### Phase 3: Human Checkpoint

The user now decides:

| User Says | What Happens |
|-----------|--------------|
| "Continue" or "Next" | Proceed to the next task in the plan. |
| "Show me" or "How do I test?" | The agent explains how to verify the current state. |
| "Change this part" | The user describes what's wrong or different from what they wanted. The agent updates the current task or the plan, re-executes if needed, and re-saves state. |
| "Go back" | Revert to the previous checkpoint and redo from there. |
| "Skip to task N" | Jump to a later task (only if earlier tasks are complete). |
| "This is wrong, stop" | Halt the story. Save state. Do not proceed until the user clarifies. |

### Phase 4: Complete

When all tasks are done:
1. Final verification — run the full test suite.
2. Final docs update — ensure architecture docs match the implemented system.
3. Final traceability check — ensure every requirement has a test and a doc reference.
4. Mark the story as complete in the Story Checkpoint file.

---

## Story Checkpoint File Format

Every story lives in `docs/roster-vault/stories/`:

- **Active stories:** `docs/roster-vault/stories/story-checkpoint-<story-slug>.md` + any supporting story documents in `docs/roster-vault/stories/<story-slug>/`
- **Archived stories:** `docs/roster-vault/stories/archive/` — one file per story, moved there on completion.

**Checkpoint filename:** `story-checkpoint-<story-slug>.md`

**Example:** `docs/roster-vault/stories/story-checkpoint-mvp.md`

**Contents:**

```markdown
# Story Checkpoint: <Story Name>

## Story Goal
<one or two sentences>

## Complexity Score
<n> (<Small|Medium|Large>)

## Status
IN PROGRESS — Task <n> of <total> complete

---

## Task 1: <name>
- **Status:** COMPLETE
- **What changed:** ...
- **Verified by:** ...
- **Files changed:** ...
- **Checkpoint saved:** <timestamp>

## Task 2: <name>
- **Status:** NOT STARTED
- **Depends on:** Task 1

---

## Plan Changes Log

- **<timestamp>:** <what changed and why>

---

## Notes
- <anything worth remembering between sessions>
```

---

## Vector Change Protocol

Mid-story direction changes are expected. The Story Agent handles them without panic or starting over.

### Types of Vector Change

1. **Scope change:** "Also support a 90-day TTL for one client's policy" — add a new task or expand an existing one.
2. **Approach change:** "Don't use KMS for signing, use a device-local root key instead" — revert the current task to the previous checkpoint, update the plan, and re-execute.
3. **Priority change:** "Skip roster switching for now, get single-user offline sign-in solid first" — reorder tasks.
4. **Clarification:** "That's not what I meant by epoch" — re-explain the requirement, update the task description, and re-execute.
5. **Emergency stop:** "Stop everything" — halt immediately, save state, wait for instructions.

### How to Apply a Vector Change

1. Acknowledge the change. Do not argue.
2. Identify which tasks are affected (current, previous, future).
3. If the change invalidates completed work, revert to the last valid checkpoint.
4. Update the Story Plan and the Checkpoint file.
5. Re-execute from the affected task forward.
6. Log the change in the Plan Changes Log.

> **Rule:** Never silently change the plan. Always announce the change, update the checkpoint file, and get user confirmation before proceeding.

---

## Agent Directives

When the Story Agent is active, the IDE AI must:

1. **Never skip the checkpoint.** Even if a task seems trivial, save state and pause for user confirmation.
2. **Never hide failures.** If a task doesn't compile or a test fails, report it immediately. Do not proceed to the next task.
3. **Never assume context.** Each task should be executable by someone reading the checkpoint file alone.
4. **Always announce the plan first.** No code is written until the user approves the Story Plan.
5. **Always log plan changes.** The checkpoint file is the source of truth. If the plan changes, the file changes.
6. **Never claim "offline" without proving it.** A task that touches sign-in verification is not complete until demonstrated with connectivity actually off, not merely "reviewed to not call the network."

---

## Integration with Other Agents

| When | Spawn |
|------|-------|
| After any code change within a task | Test Agent |
| After any architecture-affecting change within a task | Docs Agent |
| Before any task touching KMS, IAM, or local key/credential storage | "Be Careful" Review Agent |
| At story completion | Traceability Agent |
