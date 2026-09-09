# Risk Register

Every row here is a real, named tradeoff of doing offline auth at all — not an implementation bug. Better the client hears it from the architecture than discovers it in an incident review.

| Risk | Severity | Mitigation |
|---|---|---|
| Device clock set backward to extend a token's life | Medium | Persist the highest server timestamp ever seen locally; refuse sign-in if the device clock falls behind that stored high-water mark. |
| Device lost or stolen inside the TTL window | High | Mandatory local factor, no skip option; lockout after repeated failed attempts, tracked per profile so one person's lockout doesn't affect another's. |
| Rooted or jailbroken hardware | Medium | Best-effort integrity check (`root`/jailbreak detection); degrade to software-wrapped keys rather than hard-block — "unmanaged" is the brief, not optional, so refusing to run at all would violate the actual requirement. |
| Terminated user keeps working until token expiry | Medium | Inherent to offline capability, not a bug — see [[Token Lifecycle and Revocation]]. Keep TTL short and state the window explicitly in any statement of work. |
| Read as literal FIDO2/WebAuthn | Low | It's FIDO2-*inspired* — per-user asymmetric credential and challenge–response, no relying-party server at time of use. Say so precisely; see [[Trust Anchors]]. |
| Biometric hardware absent or degraded on low-end shared devices | Medium | PIN fallback (Argon2id-derived local key) must be a first-class path, not an afterthought — this is shared, unmanaged hardware, likely to include older or budget devices. |
| KMS key or IAM policy scoped too broadly | High if it happens | Caught structurally, before commit, by the [[../../agents/review-agent/review-agent|Review Agent]] checklist — least privilege on `kms:Sign` / `kms:GetPublicKey`, never `kms:*`. |

## Reading This Table

Nothing here is a reason not to build the system — every row is either an accepted, explicit tradeoff of offline verification (rows 1, 3, 4, 5) or a concrete, already-planned mitigation (rows 2, 6, 7). The point of writing it down here is that a client evaluating this approach should see the full shape of what "offline" costs, not just what it enables.

## See Also

- [[Security Index]]
- [[Trust Anchors]]
- [[Token Lifecycle and Revocation]]
- [[../Management/The Actual Requirement|The Actual Requirement]]
