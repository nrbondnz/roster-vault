# Lessons Carried From where_in_nz_v3

This project is greenfield, but the working relationship isn't. A few things worth carrying forward deliberately rather than re-learning:

## Process

- **Story Agent discipline for anything non-trivial.** `where_in_nz_v3` showed this repeatedly — a feature that touches multiple layers and has real acceptance criteria goes wrong quietly if it's built in one uninterrupted pass. On a project where the core feature is "prove identity with no network," that risk is sharper, not softer. See [[../../agents/story-agent/story-agent|Story Agent]].
- **Docs stay in sync with code, not as an afterthought.** The Obsidian vault convention (this one) came directly from that project's `docs/wherewillwevisit/` vault, because letting docs drift on a security-relevant system is worse than having none.
- **Flag unexpected state instead of silently acting on it.** Whether that's an on-disk change nobody asked for, or (here, more likely) a stray value in a KMS policy or an IAM statement that looks broader than intended — surface it, don't quietly "fix" it.
- **Verify before claiming done.** `flutter analyze` / tests before every commit on that project; here, add "with the network actually off" as a second, non-negotiable check for anything touching sign-in.
- **Be transparent about wrong turns.** More than once on `where_in_nz_v3`, an early approach turned out to be wrong (an `OverflowBox` layout fix, an assumption about Google's Maps Demo Key, an assumption about a hosting provider) and the right move was a direct correction, not a quiet pivot. The same standard applies here — if an early assumption about, say, epoch semantics or key rotation turns out wrong, say so plainly and fix it.

## Technical Habits Worth Repeating

- **Never assume a live doc is accurate — check the code/infra directly before asserting how something works.** A stale belief about "how master deploys" cost real time on `where_in_nz_v3`, repeatedly, until it was traced back to a stale doc and a stale comment in a git hook. Cheap to avoid: re-check `amplify.yml`-equivalent config rather than recalling from memory.
- **Discard incidental build-tool noise before committing** — machine-specific paths, line-ending churn — but never discard something that might be someone's in-progress work without checking first.
- **Small, reviewable commits with a clear "why."** Commit messages on that project consistently explained the reason for a change, not just its mechanics — worth keeping here, especially for anything touching the trust model, where a future reader will want to know *why* a TTL or an epoch rule was chosen, not just that it was.

## See Also

- [[Project Overview]]
- [[../../agents/index|Agents Index]]
