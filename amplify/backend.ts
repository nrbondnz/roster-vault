import { defineBackend } from '@aws-amplify/backend';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as kms from 'aws-cdk-lib/aws-kms';
import { auth } from './auth/resource';

/**
 * @see https://docs.amplify.aws/react/build-a-backend/ to add storage, functions, and more
 */
const backend = defineBackend({
  auth,
});

// Core offline-auth infrastructure. Not modeled through Amplify's `data`
// construct because the enrollment/refresh contract is a custom AppSync
// mutation backed by a Lambda resolver (see Task 4), not direct model CRUD.
// See docs/roster-vault/Backend/Tech Stack Mapping.md.
const coreStack = backend.createStack('RosterVaultCore');

// Trust Anchor 1 (docs/roster-vault/Security/Trust Anchors.md) — the issuer
// signing key. SIGN_VERIFY key usage only: this key type cannot decrypt, and
// the private key material never leaves KMS. Only kms:Sign and
// kms:GetPublicKey are ever granted to any principal (the future Enrollment
// Lambda) — no broader grant. Reviewed against the "Be Careful" Review
// Agent's IAM-scope-creep checklist before this stack is committed.
//
// RemovalPolicy.DESTROY + a 7-day pending window during MVP/sandbox
// development, since no device is enrolled against this key yet and losing
// it costs nothing real. Switch to RETAIN before any deploy that has live
// enrolled devices depending on it — see the Review Agent's rollback-safety
// checklist.
const issuerSigningKey = new kms.Key(coreStack, 'IssuerSigningKey', {
  keySpec: kms.KeySpec.ECC_NIST_P256,
  keyUsage: kms.KeyUsage.SIGN_VERIFY,
  alias: 'alias/roster-vault-issuer-signing-key',
  description:
    'Roster Vault offline-capability-token issuer key (Trust Anchor 1). ' +
    'Signs offline tokens via kms:Sign; only the public half ever ships in the app, via kms:GetPublicKey.',
  removalPolicy: RemovalPolicy.DESTROY,
  pendingWindow: Duration.days(7),
});

// DeviceEnrollments (docs/roster-vault/Backend/Tech Stack Mapping.md) — one
// row per enrolled person per device.
const deviceEnrollments = new dynamodb.Table(coreStack, 'DeviceEnrollments', {
  tableName: 'DeviceEnrollments',
  partitionKey: { name: 'deviceId', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  removalPolicy: RemovalPolicy.DESTROY,
});

backend.addOutput({
  custom: {
    issuerSigningKeyArn: issuerSigningKey.keyArn,
    deviceEnrollmentsTableName: deviceEnrollments.tableName,
  },
});
