# Agents Index

This directory contains the definitions, behaviours, and operating procedures for AI sub-agents used within the **appmanagement** (Roster Vault) project. It is carried forward, deliberately, from the same discipline used on `where_in_nz_v3` — the goal is not process for its own sake, but confidence that a security-sensitive offline-auth system doesn't get built beautifully in the wrong direction.

Each agent has a specific responsibility, a defined trigger condition, and a documented output format. Agents are not optional extras — they are part of the core workflow. Every significant piece of work should involve at least one agent.

## Agent Registry

| Agent | Purpose | Trigger |
|-------|---------|---------|
| [Story Agent](story-agent/story-agent.md) | Breaks large stories into sequential, demonstrable tasks with human checkpoints between each step | User says "build me X" where X is a multi-step feature |
| [Docs Agent](docs-agent/docs-agent.md) | Updates the Obsidian architecture vault after every non-trivial code change | Every code change (new feature, API change, schema change) |
| [Test Agent](test-agent/test-agent.md) | Writes or updates unit, widget, and integration tests | Every code change |
| [Traceability Agent](traceability-agent/traceability-agent.md) | Maintains requirement-to-code traceability and flags uncovered areas | Every story or architectural change |
| ["Be Careful" Review Agent](review-agent/review-agent.md) | Safety audit for infrastructure, IAM, and — specifically here — cryptographic key handling | Before committing any `backend.ts`, KMS/IAM change, or local-storage/crypto code |

## How Agents Are Used

Agents are invoked by the IDE AI (the orchestrator) as part of the normal workflow. The human architect does not manually trigger each agent — instead, the architect's directives to the IDE AI include instructions to spawn the relevant agents for the task at hand.

For example:
> "Build offline enrollment. Follow the Story Agent protocol. Spawn the Docs Agent after each task. Spawn the Test Agent for every code change. Run the 'Be Careful' Review Agent before touching KMS or IAM."

## Adding New Agents

If a new pattern of work emerges that warrants its own agent, create a new subdirectory here with:
1. An `index.md` or `<agent-name>.md` defining purpose, trigger, and behaviour
2. A clear output format
3. Examples of how the agent responds to typical inputs

Link the new agent in the table above.
