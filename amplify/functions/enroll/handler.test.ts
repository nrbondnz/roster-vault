import { generateKeyPairSync, sign as nodeSign, verify as nodeVerify } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import { DynamoDBClient, GetItemCommand, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall } from '@aws-sdk/util-dynamodb';
import { KMSClient, SignCommand } from '@aws-sdk/client-kms';
import { mockClient } from 'aws-sdk-client-mock';
import type { AppSyncResolverEvent } from 'aws-lambda';

process.env.DEVICE_ENROLLMENTS_TABLE_NAME = 'test-enrollments-table';
process.env.ISSUER_SIGNING_KEY_ID = 'test-issuer-key-id';

// Imported after env vars are set -- handler.ts reads them at module load.
const { handler, derToRawEcdsaSignature } = await import('./handler');

const dynamoMock = mockClient(DynamoDBClient);
const kmsMock = mockClient(KMSClient);

// Real P-256 keypair, real KMS-shaped DER signature -- same discipline as
// the Dart side (pin_and_partition_test.dart: "real encryption verified",
// nothing mocked at the crypto boundary). Only the AWS SDK calls are
// mocked; the DER-to-raw conversion itself runs against genuine ECDSA
// output, not a hand-built fixture.
const issuerKeyPair = generateKeyPairSync('ec', { namedCurve: 'P-256' });

function realDerSignature(message: Buffer): Buffer {
  return nodeSign(null, message, { key: issuerKeyPair.privateKey, dsaEncoding: 'der' });
}

// Inverse of handler.ts's derToRawEcdsaSignature -- raw R||S back to DER,
// needed because Node's verify() only accepts DER. Used to prove the raw
// signature this project actually ships in the JWS still verifies, not
// just that it has the right byte length.
function encodeDerInteger(b: Buffer): Buffer {
  let v = b;
  while (v.length > 1 && v[0] === 0x00 && (v[1] & 0x80) === 0) v = v.subarray(1);
  if (v[0]! & 0x80) v = Buffer.concat([Buffer.from([0x00]), v]);
  return Buffer.concat([Buffer.from([0x02, v.length]), v]);
}

function rawToDerEcdsaSignature(raw: Buffer): Buffer {
  const r = raw.subarray(0, 32);
  const s = raw.subarray(32, 64);
  const seq = Buffer.concat([encodeDerInteger(r), encodeDerInteger(s)]);
  return Buffer.concat([Buffer.from([0x30, seq.length]), seq]);
}

function baseEvent(overrides: Partial<AppSyncResolverEvent<{ deviceId: string; devicePubKey: string; userPubKey: string }>> = {}) {
  return {
    identity: { sub: 'cognito-user-123' },
    arguments: {
      deviceId: 'device-abc',
      devicePubKey: 'device-pub-key-base64',
      userPubKey: 'user-pub-key-base64',
    },
    ...overrides,
  } as AppSyncResolverEvent<{ deviceId: string; devicePubKey: string; userPubKey: string }>;
}

describe('derToRawEcdsaSignature', () => {
  it('converts a real KMS-shaped DER signature to 64-byte raw R||S', () => {
    const der = realDerSignature(Buffer.from('signing-input-example'));
    const raw = derToRawEcdsaSignature(der);
    expect(raw).toHaveLength(64);
  });

  it('round-trips: the raw signature still verifies against the same public key', () => {
    const message = Buffer.from('another-signing-input');
    const der = realDerSignature(message);
    const raw = derToRawEcdsaSignature(der);
    const derFromRawSig = rawToDerEcdsaSignature(raw);

    expect(nodeVerify(null, message, { key: issuerKeyPair.publicKey, dsaEncoding: 'der' }, derFromRawSig)).toBe(true);
  });

  it('strips DER leading-zero padding and re-pads to exactly 32 bytes', () => {
    // A hand-built DER signature whose r has a 0x00 padding byte (high bit
    // of the next byte set) and whose s is short enough to need re-padding
    // -- the two edge-case branches the real-signature tests above may not
    // reliably hit, since padding depends on the random nonce each ECDSA
    // signature uses.
    const r = Buffer.concat([Buffer.from([0x00]), Buffer.alloc(31, 0xff), Buffer.from([0x01])]); // 33 bytes, needs stripping
    const rInt = Buffer.concat([Buffer.from([0x02, r.length]), r]);
    const s = Buffer.from([0x01, 0x02, 0x03]); // 3 bytes, needs re-padding to 32
    const sInt = Buffer.concat([Buffer.from([0x02, s.length]), s]);
    const seq = Buffer.concat([rInt, sInt]);
    const der = Buffer.concat([Buffer.from([0x30, seq.length]), seq]);

    const raw = derToRawEcdsaSignature(der);
    expect(raw).toHaveLength(64);
    expect(raw.subarray(0, 32)).toEqual(Buffer.concat([Buffer.alloc(31, 0xff), Buffer.from([0x01])]));
    expect(raw.subarray(32, 64)).toEqual(Buffer.concat([Buffer.alloc(29), Buffer.from([0x01, 0x02, 0x03])]));
  });

  it('rejects a non-SEQUENCE input as invalid DER', () => {
    expect(() => derToRawEcdsaSignature(Buffer.from([0x04, 0x02, 0x00, 0x00]))).toThrow('expected SEQUENCE');
  });
});

describe('enroll handler', () => {
  beforeEach(() => {
    dynamoMock.reset();
    kmsMock.reset();
    kmsMock.on(SignCommand).callsFake((input) => ({
      Signature: realDerSignature(Buffer.from(input.Message as Uint8Array)),
    }));
  });

  it('rejects a request with no verified Cognito identity', async () => {
    const event = baseEvent({ identity: undefined });
    await expect(handler(event, {} as never, undefined as never)).rejects.toThrow('no verified Cognito identity');
  });

  it('rejects a request missing required arguments', async () => {
    const event = baseEvent({ arguments: { deviceId: '', devicePubKey: 'x', userPubKey: 'y' } });
    await expect(handler(event, {} as never, undefined as never)).rejects.toThrow('deviceId, devicePubKey, and userPubKey are all required');
  });

  it('first-time enrollment starts at epoch 0 and writes an active record', async () => {
    dynamoMock.on(GetItemCommand).resolves({});
    dynamoMock.on(PutItemCommand).resolves({});

    const result = await handler(baseEvent(), {} as never, undefined as never);

    expect(result?.epoch).toBe(0);
    expect(typeof result?.token).toBe('string');
    expect(result?.token.split('.')).toHaveLength(3); // header.payload.signature

    const putCalls = dynamoMock.commandCalls(PutItemCommand);
    expect(putCalls).toHaveLength(1);
    expect(putCalls[0]!.args[0].input.Item).toMatchObject(
      marshall({
        deviceId: 'device-abc',
        userId: 'cognito-user-123',
        epoch: 0,
        status: 'active',
      }),
    );
  });

  it('re-enrollment preserves the existing epoch rather than resetting it', async () => {
    dynamoMock.on(GetItemCommand).resolves({
      Item: marshall({
        deviceId: 'device-abc',
        userId: 'cognito-user-123',
        epoch: 3,
        status: 'active',
      }),
    });
    dynamoMock.on(PutItemCommand).resolves({});

    const result = await handler(baseEvent(), {} as never, undefined as never);

    expect(result?.epoch).toBe(3);
    const putCalls = dynamoMock.commandCalls(PutItemCommand);
    expect(putCalls[0]!.args[0].input.Item).toMatchObject(marshall({ epoch: 3, status: 'active' }));
  });

  it('refuses to re-enroll a device whose enrollment has been revoked', async () => {
    dynamoMock.on(GetItemCommand).resolves({
      Item: marshall({
        deviceId: 'device-abc',
        userId: 'cognito-user-123',
        epoch: 5,
        status: 'revoked',
      }),
    });

    await expect(handler(baseEvent(), {} as never, undefined as never)).rejects.toThrow('this enrollment has been revoked');

    // Task 8's own reasoning (handler.ts comment): a revoked row must never
    // reach the unconditional PutItemCommand, or that write would silently
    // un-revoke it. Assert the write never happened, not just that the
    // handler threw for some other reason.
    expect(dynamoMock.commandCalls(PutItemCommand)).toHaveLength(0);
  });

  it('signs the token with the real issuer key via KMS, not a stub', async () => {
    dynamoMock.on(GetItemCommand).resolves({});
    dynamoMock.on(PutItemCommand).resolves({});

    const result = await handler(baseEvent(), {} as never, undefined as never);

    const [headerB64, payloadB64, sigB64] = result!.token.split('.');
    const signingInput = `${headerB64}.${payloadB64}`;
    const derSig = rawToDerEcdsaSignature(Buffer.from(sigB64!, 'base64url'));

    expect(
      nodeVerify(null, Buffer.from(signingInput, 'utf8'), { key: issuerKeyPair.publicKey, dsaEncoding: 'der' }, derSig),
    ).toBe(true);

    const payload = JSON.parse(Buffer.from(payloadB64!, 'base64url').toString('utf8'));
    expect(payload).toMatchObject({
      user_id: 'cognito-user-123',
      device_id: 'device-abc',
      scopes: ['offline_signin'],
      epoch: 0,
    });
  });
});
