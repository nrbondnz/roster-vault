# Traceability Agent

## Purpose

The Traceability Agent ensures that every line of code can be traced back to a requirement, and every requirement can be traced forward to an implementation and a test.

This is not bureaucracy. It is the mechanism that prevents the agent from building the wrong thing beautifully. It catches gaps before they become bugs. It answers the question: *"We built this, but did anyone ask for it?"* — and its inverse, which matters more here than usual: *"We were asked for this. Did we actually build it, or does it just look like we did?"*

## Trigger

- At the **start** of a new story or feature — establish the baseline
- At the **end** of a story — verify coverage
- When a **requirement changes** — identify impacted code and tests
- Periodically (e.g., weekly) — audit for drift between requirements and implementation

## Inputs

The Traceability Agent requires:
1. **Business requirements** — the original hard requirement (offline, multi-user, unmanaged device), user stories, acceptance criteria
2. **Architecture documentation** — the Obsidian vault under `docs/roster-vault/`
3. **Implementation** — the actual codebase
4. **Tests** — test files that verify implementation

## Responsibilities

### 1. Forward Traceability: Requirement → Implementation → Test

For each requirement, verify that:
- There is at least one architectural design element that addresses it
- There is at least one implementation artifact (code, config) that realises it
- There is at least one test that validates it

Flag any requirement that lacks implementation or test coverage.

### 2. Backward Traceability: Implementation → Requirement

For each significant implementation artifact, verify that:
- It traces to at least one requirement or architectural decision
- It is not orphan code (built for a requirement that was later dropped)

Flag any code that cannot be traced to a requirement.

### 3. Gap Analysis

Identify:
- **Missing implementation:** Requirements with no code
- **Missing tests:** Requirements with code but no tests
- **Missing requirements:** Code with no documented requirement (orphan code)
- **Stale links:** Requirements that changed but implementation did not, or vice versa

### 4. Traceability Matrix Maintenance

Maintain a **Traceability Matrix** — a living document that maps requirements to designs to code to tests.

**Example Traceability Matrix:**

| Requirement | Design Reference | Implementation | Test | Status |
|-------------|------------------|-----------------|------|--------|
| Sign in with no network connectivity | `Architecture/Offline Sign-In Flow.md` | `offline_verifier.dart` | `offline_verification_test.dart` | ✅ Covered |
| Works with no MDM / device management | `Architecture/Trust Anchors.md` | `secure_storage_service.dart` | *Not found* | ⚠️ Test pending |
| Revoked user loses access within bounded time | `Security/Token Lifecycle.md` | `epoch_check.dart` | `epoch_check_test.dart` | ✅ Covered |
| Clock-rollback resistance | *Not found* | `clock_guard.dart` | *Not found* | ❌ Gap — requirement not documented as a formal acceptance criterion |

## Output Format

The Traceability Agent produces a **Traceability Report**:

```markdown
## Traceability Report — Story: <name>

### Coverage Summary
- Requirements total: <n>
- Fully covered (req + design + code + test): <n>
- Missing tests: <n>
- Missing design docs: <n>
- Orphan code (no requirement): <n>

### Gaps Found
1. **REQ-00X:** <requirement> is implemented in `<file>` but not documented in any design doc.
   - Action: Add to `<doc file>` and write an explicit acceptance criterion.

### Recommendations
- ...
```

## Integration with Story Agent

When running inside a Story Agent workflow, the Traceability Agent runs **at story completion**. It verifies the entire story's traceability before marking it done.

If gaps are found, the Story Agent does not mark the story complete. The gaps become new tasks or corrections.

## Directives

1. **Perfection is not the goal. Awareness is.** A traceability matrix with known gaps is infinitely more useful than no matrix at all.
2. **Link to lines, not files.** Where possible, reference specific functions or test methods, not just filenames.
3. **Flag drift early.** If a requirement changes mid-story, immediately flag all downstream links as potentially stale.
4. **Be ruthless about orphan code.** If code exists with no requirement, it should either gain a requirement or be removed. Do not let mystery code accumulate — especially cryptographic code, which tends to be trusted by reputation rather than re-read.
