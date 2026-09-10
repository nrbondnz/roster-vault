import { DynamoDBClient, GetItemCommand, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb';
import { KMSClient, SignCommand } from '@aws-sdk/client-kms';
import type { AppSyncResolverHandler } from 'aws-lambda';

// Task 4a -- Enrollment Lambda resolver for the `enroll` mutation
// (amplify/appsync/schema.graphql). See docs/roster-vault/Architecture/Enrollment Flow.md
// and docs/roster-vault/Security/Trust Anchors.md (Anchor 1, Issuer Key).
//
// AppSync's Cognito User Pool authorizer has already verified the caller's
// ID token before this handler ever runs -- ctx.identity.sub below is a
// verified claim, not something this function re-checks.

type EnrollArgs = {
  deviceId: string;
  devicePubKey: string;
  userPubKey: string;
};

type EnrollResult = {
  token: string;
  epoch: number;
  expiresAt: number;
};

const dynamo = new DynamoDBClient({});
const kms = new KMSClient({});

const TABLE_NAME = process.env.DEVICE_ENROLLMENTS_TABLE_NAME!;
const ISSUER_KEY_ID = process.env.ISSUER_SIGNING_KEY_ID!;
const TOKEN_TTL_SECONDS = 48 * 60 * 60; // 48h, mid-point of the 24-72h range noted in the checkpoint's Notes -- a policy knob, not fixed by the architecture.

function base64url(input: Buffer): string {
  return input.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// KMS returns an ECDSA signature as a DER-encoded SEQUENCE of two INTEGERs
// (r, s). JWS ES256 (RFC 7518 3.4) instead requires the fixed-width raw
// concatenation R || S, each 32 bytes for P-256, left-zero-padded. This is
// the one non-obvious wire-format conversion in the whole handler.
export function derToRawEcdsaSignature(der: Uint8Array): Buffer {
  let offset = 0;
  if (der[offset++] !== 0x30) throw new Error('Invalid DER signature: expected SEQUENCE');
  let seqLen = der[offset++];
  if (seqLen & 0x80) {
    const numBytes = seqLen & 0x7f;
    seqLen = 0;
    for (let i = 0; i < numBytes; i++) seqLen = (seqLen << 8) | der[offset++];
  }

  function readInt(): Buffer {
    if (der[offset++] !== 0x02) throw new Error('Invalid DER signature: expected INTEGER');
    let len = der[offset++];
    if (len & 0x80) {
      const numBytes = len & 0x7f;
      len = 0;
      for (let i = 0; i < numBytes; i++) len = (len << 8) | der[offset++];
    }
    const bytes = Buffer.from(der.slice(offset, offset + len));
    offset += len;
    return bytes;
  }

  let r = readInt();
  let s = readInt();

  // DER left-pads INTEGERs with 0x00 when the high bit would otherwise be
  // set (to keep them non-negative); strip that back off, then re-pad to
  // exactly 32 bytes for the raw fixed-width format.
  const fixTo32 = (b: Buffer): Buffer => {
    let v = b;
    while (v.length > 32 && v[0] === 0x00) v = v.subarray(1);
    if (v.length > 32) throw new Error('Invalid DER signature: integer too long for P-256');
    if (v.length < 32) v = Buffer.concat([Buffer.alloc(32 - v.length), v]);
    return v;
  };

  return Buffer.concat([fixTo32(r), fixTo32(s)]);
}

async function signToken(payload: Record<string, unknown>): Promise<string> {
  const header = { alg: 'ES256', typ: 'JWT' };
  const signingInput = `${base64url(Buffer.from(JSON.stringify(header)))}.${base64url(Buffer.from(JSON.stringify(payload)))}`;

  const { Signature } = await kms.send(
    new SignCommand({
      KeyId: ISSUER_KEY_ID,
      Message: Buffer.from(signingInput, 'utf8'),
      MessageType: 'RAW',
      SigningAlgorithm: 'ECDSA_SHA_256',
    }),
  );
  if (!Signature) throw new Error('KMS did not return a signature');

  const rawSig = derToRawEcdsaSignature(Signature);
  return `${signingInput}.${base64url(rawSig)}`;
}

export const handler: AppSyncResolverHandler<EnrollArgs, EnrollResult> = async (event) => {
  const userId = event.identity && 'sub' in event.identity ? (event.identity as { sub: string }).sub : undefined;
  if (!userId) {
    throw new Error('enroll: no verified Cognito identity on the request (unexpected -- AppSync should have rejected this before it reached the resolver)');
  }

  const { deviceId, devicePubKey, userPubKey } = event.arguments;
  if (!deviceId || !devicePubKey || !userPubKey) {
    throw new Error('enroll: deviceId, devicePubKey, and userPubKey are all required');
  }

  // Preserve any existing epoch across re-enrollment/refresh -- epoch is
  // only ever bumped by an explicit admin revocation action (Task 8), never
  // reset by the person re-enrolling themselves.
  const existing = await dynamo.send(
    new GetItemCommand({
      TableName: TABLE_NAME,
      Key: marshall({ deviceId, userId }),
    }),
  );
  const existingItem = existing.Item ? unmarshall(existing.Item) : undefined;

  // Task 8 -- revocation. An admin action bumps this row's epoch AND sets
  // status: 'revoked' in the same write (see docs/roster-vault/Security/Token
  // Lifecycle and Revocation.md and the story checkpoint's Task 8 entry for
  // why both together, not epoch alone: nothing in this table format lets a
  // stateless Lambda compare "the device's last known epoch" against "the
  // current epoch" -- that comparison only exists on-device, in
  // OfflineVerifier. The *online* gate has to be a separate, explicit flag
  // the Lambda can actually check server-side.
  //
  // Checked and refused *before* any write below -- if this fell through to
  // the PutItemCommand first, that unconditional `status: 'active'` would
  // silently un-revoke the row on every subsequent refresh attempt, which
  // would make revocation impossible to enforce online at all.
  if (existingItem?.status === 'revoked') {
    throw new Error('enroll: this enrollment has been revoked');
  }

  const epoch = existingItem ? (existingItem.epoch as number) : 0;

  const nowSeconds = Math.floor(Date.now() / 1000);
  const expiresAt = nowSeconds + TOKEN_TTL_SECONDS;

  await dynamo.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: marshall({
        deviceId,
        userId,
        devicePubKey,
        userPubKey,
        epoch,
        status: 'active',
        lastIssuedExpiry: expiresAt,
      }),
    }),
  );

  const token = await signToken({
    user_id: userId,
    device_id: deviceId,
    scopes: ['offline_signin'],
    epoch,
    iat: nowSeconds,
    exp: expiresAt,
  });

  return { token, epoch, expiresAt };
};
