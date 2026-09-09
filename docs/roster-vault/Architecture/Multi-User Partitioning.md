# Multi-User Partitioning

One device, several people. Each name on the roster is a hard data boundary, not a UI skin over one shared database.

## Fast Switching

Signing out locks that person's partition and returns to the roster. No round trip, no re-provisioning — the next person's [[Offline Sign-In Flow|sign-in]] starts from the same locally cached roster.

## Real Partitioning, Not Just a UI Filter

Each person's local data is encrypted under its own key, derived as:

```
K_user = HKDF(K_device, user_id)
```

Someone with raw file access to the device — a lost tablet, a forensic pull — still can't read another profile's data without that profile's own local factor. This is the difference between "the app shows you your own data" (a UI-level guarantee, worthless if the storage itself is one shared blob) and "the data is only decryptable if you are that person" (a real one).

## Roster Management Is an Online-Only Surface

Adding a person, removing a person, or forcing a refresh all go through the same enrollment API described in [[Enrollment Flow]]. When the device has no connection, this surface is simply unavailable — greyed out, honestly, rather than silently failing or queuing something that can't actually complete offline.

## See Also

- [[Architecture Index]]
- [[Offline Sign-In Flow]]
- [[../Security/Token Lifecycle and Revocation|Token Lifecycle and Revocation]]
