import { defineBackend } from '@aws-amplify/backend';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as kms from 'aws-cdk-lib/aws-kms';
import { auth } from './auth/resource';
import { enroll } from './functions/enroll/resource';

/**
 * @see https://docs.amplify.aws/react/build-a-backend/ to add storage, functions, and more
 */
const backend = defineBackend({
  auth,
  enroll,
});

// Task 4a verification needs a way to obtain a real Cognito ID token from
// the CLI (to call `enroll` directly, before any Flutter login screen
// exists in Task 4b). ALLOW_ADMIN_USER_PASSWORD_AUTH is scoped to callers
// who already hold AWS IAM credentials with cognito-idp:AdminInitiateAuth
// (i.e. this project's own AWS access, not any app end-user) -- deliberately
// not the broader ALLOW_USER_PASSWORD_AUTH, which would expose direct
// password auth to any client calling this app's Cognito client id. The
// only end-user-facing flow remains ALLOW_USER_SRP_AUTH, unchanged.
// Autonomous decision, logged in the story checkpoint's Plan Changes Log.
backend.auth.resources.cfnResources.cfnUserPoolClient.explicitAuthFlows = [
  'ALLOW_ADMIN_USER_PASSWORD_AUTH',
  'ALLOW_CUSTOM_AUTH',
  'ALLOW_REFRESH_TOKEN_AUTH',
  'ALLOW_USER_SRP_AUTH',
];

// Core offline-auth infrastructure. Not modeled through Amplify's `data`
// construct because the enrollment/refresh contract is a custom AppSync
// mutation backed by a Lambda resolver (see Task 4), not direct model CRUD.
// See docs/roster-vault/Backend/Tech Stack Mapping.md.
//
// This stack is obtained via backend.enroll.stack (resourceGroupName:
// 'RosterVaultCore' in amplify/functions/enroll/resource.ts), not via a
// separate backend.createStack('RosterVaultCore') call. Doing both throws
// ("Custom stack named RosterVaultCore has already been created") -- and
// creating the function in a *different* stack than the KMS key/table it's
// granted access to produces a circular nested-stack dependency once
// backend.enroll is granted access to resources that live in a stack which
// itself needs the function's ARN for the AppSync data source below. Hit
// and fixed during Task 4a; see story checkpoint Plan Changes Log.
const coreStack = backend.enroll.stack;

// Trust Anchor 1 (docs/roster-vault/Security/Trust Anchors.md) — the issuer
// signing key. SIGN_VERIFY key usage only: this key type cannot decrypt, and
// the private key material never leaves KMS. Only kms:Sign and
// kms:GetPublicKey are ever granted to any principal (the Enrollment
// Lambda, granted below) — no broader grant. Reviewed against the "Be
// Careful" Review Agent's IAM-scope-creep checklist before this stack is
// committed (Task 4a self-review, see story checkpoint).
//
// RemovalPolicy.DESTROY + a 7-day pending window during MVP/sandbox
// development, since no device is enrolled against this key yet and losing
// it costs nothing real. Switch to RETAIN before any deploy that has live
// enrolled devices depending on it — see the Review Agent's rollback-safety
// checklist.
const issuerSigningKey = new kms.Key(coreStack, 'IssuerSigningKey', {
  keySpec: kms.KeySpec.ECC_NIST_P256,
  keyUsage: kms.KeyUsage.SIGN_VERIFY,
  alias: `alias/roster-vault-issuer-signing-key-${coreStack.stackName}`,
  description:
    'Roster Vault offline-capability-token issuer key (Trust Anchor 1). ' +
    'Signs offline tokens via kms:Sign; only the public half ever ships in the app, via kms:GetPublicKey.',
  removalPolicy: RemovalPolicy.DESTROY,
  pendingWindow: Duration.days(7),
});

// DeviceEnrollments (docs/roster-vault/Backend/Tech Stack Mapping.md) — one
// row per enrolled person per device.
const deviceEnrollments = new dynamodb.Table(coreStack, 'DeviceEnrollments', {
  partitionKey: { name: 'deviceId', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  removalPolicy: RemovalPolicy.DESTROY,
});

// --- Task 4a: enrollment API -------------------------------------------
//
// A single custom mutation, Cognito User Pool-authorized. AppSync itself
// verifies the caller's ID token before the resolver runs; the Lambda
// trusts ctx.identity.sub as already-verified. Schema lives in
// amplify/appsync/schema.graphql — see docs/roster-vault/Architecture/Enrollment Flow.md.
const enrollApi = new appsync.GraphqlApi(coreStack, 'EnrollmentApi', {
  // Unlike the KMS alias below, AppSync API names have a 100-char cap and
  // don't need to be globally unique (uniqueness is by apiId, assigned by
  // AWS) -- so no stack-name suffix needed here. Hit the length limit with
  // the stack-name-suffixed version first; see story checkpoint.
  name: 'roster-vault-enrollment-api',
  definition: appsync.Definition.fromFile('amplify/appsync/schema.graphql'),
  authorizationConfig: {
    defaultAuthorization: {
      authorizationType: appsync.AuthorizationType.USER_POOL,
      userPoolConfig: {
        userPool: backend.auth.resources.userPool,
      },
    },
  },
  xrayEnabled: false,
});

const enrollFn = backend.enroll.resources.lambda;

// Scoped grants only: kms:Sign (never Decrypt -- this key can't decrypt,
// it's SIGN_VERIFY-only), and exactly the two DynamoDB actions the handler
// actually calls (GetItem to read any existing epoch, PutItem to write the
// row) -- not the broader grantReadWriteData() helper, which would also
// hand out Query/Scan/DeleteItem/BatchWriteItem the handler never uses.
// Tightened during Task 4a's Review Agent self-check; see story checkpoint.
issuerSigningKey.grant(enrollFn, 'kms:Sign');
deviceEnrollments.grant(enrollFn, 'dynamodb:GetItem', 'dynamodb:PutItem');

// addEnvironment lives on the function *factory* (backend.enroll), not on
// the resolved IFunction resource (backend.enroll.resources.lambda) --
// IFunction doesn't expose it.
backend.enroll.addEnvironment('ISSUER_SIGNING_KEY_ID', issuerSigningKey.keyId);
backend.enroll.addEnvironment('DEVICE_ENROLLMENTS_TABLE_NAME', deviceEnrollments.tableName);

const enrollDataSource = enrollApi.addLambdaDataSource('EnrollLambdaDataSource', enrollFn);
enrollDataSource.createResolver('EnrollResolver', {
  typeName: 'Mutation',
  fieldName: 'enroll',
});

backend.addOutput({
  custom: {
    issuerSigningKeyArn: issuerSigningKey.keyArn,
    issuerSigningKeyId: issuerSigningKey.keyId,
    deviceEnrollmentsTableName: deviceEnrollments.tableName,
    // Not Amplify's own `api` output shape (this isn't registered through
    // Amplify's `data` category) -- the Flutter app calls this as a plain
    // HTTPS GraphQL POST with the Cognito ID token as the Authorization
    // header, rather than through the typed amplify_api client. See Task 4c.
    enrollApiUrl: enrollApi.graphqlUrl,
    enrollApiId: enrollApi.apiId,
  },
});
