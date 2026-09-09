# The Actual Requirement

Restated precisely, because the precision is what disqualifies the obvious answer:

- **Multiple users** share one physical device — not one login per device.
- **Offline at sign-in** — no network call to an identity provider is allowed at the moment someone authenticates.
- **Unmanaged** — no MDM, no domain join, no OS-cached-logon trick to lean on.

That combination is genuinely uncommon. Standard SSO/OIDC solves "prove who you are," but only when a live round trip to the identity provider is available at sign-in — which is precisely the one thing this environment cannot offer. It also implicitly assumes one user per device/session, which a shared-device roster breaks on its own even before offline enters the picture.

## Why the Obvious Fixes Don't Work

| Obvious answer | Why it doesn't apply here |
|---|---|
| "Just use OIDC/SSO" | Requires a live call to the IdP at sign-in. That's the one thing ruled out. |
| "Use MDM / device management" | Explicitly ruled out — the device is unmanaged. |
| "Cache the OS login" | There's no single OS account to cache — multiple people share the device, and unmanaged hardware won't reliably offer this anyway. |
| "One shared device PIN" | Fails "attributable" — it doesn't tell you *which* person is signed in, and can't be revoked per-person. |

## Reframe

The app becomes its own small identity provider for a bounded window of time. Cognito still does one job well — proving who someone is *while online* — but everything after that, including every offline sign-in for days afterward, is verified locally against material Cognito helped issue earlier. That's the entire shape of [[Enrollment Flow]] and [[Offline Sign-In Flow]].

## What "Solved" Looks Like

- A person can pick their name from a roster on the device and sign in with a local PIN or biometric, with the device in airplane mode, and the app correctly proves it's them.
- A person removed from the roster loses access within a bounded, known time window — see [[Token Lifecycle and Revocation]] — even though the device may never reconnect to confirm the removal.
- None of this requires the device to be enrolled in any MDM product, or to have a single OS-level account per person.

## See Also

- [[Project Overview]]
- [[Trust Anchors]]
- [[Risk Register]] — the tradeoffs this reframe accepts, made explicit
