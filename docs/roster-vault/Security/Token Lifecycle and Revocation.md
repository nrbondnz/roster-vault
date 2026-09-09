# Token Lifecycle and Revocation

You can't push a revocation to a device that isn't listening. So risk here is controlled going in, not pulled back after the fact.

| Mechanism | What it does | Where it lives |
|---|---|---|
| Short TTL | Bounds how long a lost or terminated credential keeps working offline, with no other control in play. | Claim on the JWT — 24–72 hours, tunable per deployment |
| Silent refresh | On reconnect, the app quietly re-requests tokens for every enrolled person on the device — no re-login prompt. | Foreground hook + `connectivity_plus`, calling the same [[../Architecture/Enrollment Flow|enrollment endpoint]] |
| Epoch counter | Bumped the moment someone is terminated or flagged. A device must reconnect once, post-bump, before it can renew — old tokens simply age out rather than being actively revoked. | `epoch` field on the `DeviceEnrollments` record in DynamoDB |

## The Epoch Model, Precisely

- Every offline token carries the epoch value that was current when it was issued.
- [[../Architecture/Offline Sign-In Flow|Offline sign-in]] checks the token's epoch against the epoch stored on-device from the last successful enrollment/refresh — **not** against a live server value, since there is none available.
- When someone is terminated, an admin action (or an event-driven Lambda reacting to a business event) increments the epoch in DynamoDB.
- The device's *stored* epoch doesn't change until it next reconnects and refreshes — at which point the refresh either succeeds (device epoch catches up, new token issued) or is refused for that specific user (if they were the one terminated), even though the device is online again.
- Critically: this means a terminated person's **existing, already-issued token keeps working locally until it naturally expires**, if the device never reconnects in the meantime. That's not a bug in the model — it's the actual, load-bearing tradeoff of "no live revocation channel." See [[Risk Register]].

## Comparison Direction Matters

Verification must reject when `token.epoch < currentKnownEpoch` — an old token, superseded by a bump. It must **not** be written the other way around (rejecting newer epochs), which would lock out a device that refreshed successfully. This exact inversion is the kind of one-character bug the [[../../agents/review-agent/review-agent|Review Agent]] checklist exists to catch.

## Refresh, in Practice

Refresh reuses [[../Architecture/Enrollment Flow|Enrollment Flow]]'s Lambda, called opportunistically whenever the app is foregrounded with connectivity, for every profile enrolled on that device — not just the currently signed-in one. This is what keeps the "24–72 hour" TTL from meaning "this app is only usable for three days between visits to head office" in practice, as long as the device gets *any* connectivity within that window.

## See Also

- [[Security Index]]
- [[Trust Anchors]]
- [[Risk Register]]
- [[../Architecture/Enrollment Flow|Enrollment Flow]]
