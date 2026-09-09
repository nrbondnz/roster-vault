import { defineFunction } from '@aws-amplify/backend';

// Task 4a -- the enrollment Lambda. Reads/writes DeviceEnrollments and calls
// kms:Sign on the issuer key; both grants are added explicitly in
// amplify/backend.ts (scoped to exactly these two actions, nothing broader).
export const enroll = defineFunction({
  name: 'enroll',
  entry: './handler.ts',
  timeoutSeconds: 10,
  // Without this, Amplify puts the function in its own default "function"
  // nested stack, which creates a circular dependency once backend.ts grants
  // it access to resources (KMS key, table, AppSync data source) that live
  // in the custom RosterVaultCore stack -- the two nested stacks end up
  // depending on each other. Grouping it into RosterVaultCore directly
  // (same stack as everything it's granted access to) avoids the cycle.
  // Hit and fixed during Task 4a; see story checkpoint Plan Changes Log.
  resourceGroupName: 'RosterVaultCore',
});
