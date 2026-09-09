# Project Overview

**Roster Vault** is a Flutter application, backed by AWS Amplify Gen 2, built to solve one specific and genuinely uncommon problem: letting several people share one physical device and each sign in as themselves, verified locally, with zero network connectivity at the moment of sign-in, and without any OS-level device management (no MDM, no domain join).

## Who This Is For

Shared, unmanaged hardware in environments where connectivity is unreliable or absent by design — field teams, delivery routes, ward devices, site tablets — where a device is handed between several named people over a shift, and each person's access has to be individually attributable and individually revocable, without assuming the device can ever "phone home" at the moment someone needs to use it.

## Why Standard Approaches Don't Fit

See [[The Actual Requirement]] for the full argument. In short: OIDC/SSO, MDM-based device trust, and cached domain logons all assume something this environment doesn't have — either live connectivity, or an OS/MDM layer willing to manage the device. The app itself has to become a small, bounded identity verifier, working from material provisioned the last time it *did* have a connection.

## Stack

- **Client:** Flutter (iOS + Android)
- **Backend:** AWS Amplify Gen 2 — Cognito (online identity only), AppSync, Lambda, KMS, DynamoDB
- **Local trust:** platform Keystore/Keychain, `flutter_secure_storage`, per-user encrypted local database

See [[Tech Stack Mapping]] for the full, concrete breakdown of what implements what.

## Where to Start Reading

1. [[The Actual Requirement]] — the problem, restated precisely
2. [[Trust Anchors]] — the three pieces of key material everything else depends on
3. [[Enrollment Flow]] then [[Offline Sign-In Flow]] — the two flows that matter most
4. [[story-checkpoint-mvp|Story Checkpoint: MVP]] — the actual build plan, in order

## See Also

- [[Management Index]]
- [[Lessons Carried From where_in_nz_v3]]
