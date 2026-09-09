import 'dart:async';
import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'screens/login_screen.dart';
import 'services/device_identity_service.dart';
import 'services/enrollment_service.dart';
import 'services/issuer_public_key.dart';
import 'services/offline_verifier.dart';
import 'services/token_verifier.dart';
import 'services/user_identity_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RosterVaultApp());
}

class RosterVaultApp extends StatelessWidget {
  const RosterVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Vault',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const _AuthGate(),
    );
  }
}

/// Task 4b — configures Amplify once, then routes to [LoginScreen] or
/// straight to [DeviceDebugScreen] depending on whether a Cognito session
/// already exists (e.g. after a hot restart). The one online step in the
/// whole system (docs/roster-vault/Architecture/Enrollment Flow.md step 1)
/// happens in [LoginScreen]; everything downstream of a successful sign-in
/// is what Task 4c (enrollment) and beyond build on.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

enum _AuthGateStatus { loading, signedOut, signedIn, error }

class _AuthGateState extends State<_AuthGate> {
  _AuthGateStatus _status = _AuthGateStatus.loading;
  AuthUser? _user;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (!Amplify.isConfigured) {
        final configJson = await rootBundle.loadString('amplify_outputs.json');
        // Sanity-check it parses before handing it to Amplify, so a missing
        // or malformed amplify_outputs.json fails with a clear message
        // instead of an opaque Amplify plugin error.
        jsonDecode(configJson);
        await Amplify.addPlugins([AmplifyAuthCognito()]);
        await Amplify.configure(configJson);
      }
      final user = await Amplify.Auth.getCurrentUser();
      setState(() {
        _user = user;
        _status = _AuthGateStatus.signedIn;
      });
    } on SignedOutException {
      setState(() => _status = _AuthGateStatus.signedOut);
    } catch (e) {
      setState(() {
        _errorText = 'Amplify configuration failed: $e';
        _status = _AuthGateStatus.error;
      });
    }
  }

  void _onSignedIn(AuthUser user) {
    setState(() {
      _user = user;
      _status = _AuthGateStatus.signedIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _AuthGateStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _AuthGateStatus.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_errorText ?? 'Unknown error', style: const TextStyle(color: Colors.red)),
            ),
          ),
        );
      case _AuthGateStatus.signedOut:
        return LoginScreen(onSignedIn: _onSignedIn);
      case _AuthGateStatus.signedIn:
        return DeviceDebugScreen(deviceIdentityService: DeviceIdentityService(), signedInUser: _user);
    }
  }
}

/// Development-only screen. Shows this device's identity material so it can
/// be inspected during Task 3 (device keypair generation) and beyond.
/// Never shown in a release build's normal flow — the real entry point is
/// the roster screen (Task 7).
class DeviceDebugScreen extends StatefulWidget {
  const DeviceDebugScreen({super.key, required this.deviceIdentityService, this.signedInUser});

  final DeviceIdentityService deviceIdentityService;

  /// Task 4b — set once Cognito sign-in (LoginScreen) succeeds. Displayed
  /// so the on-screen authenticated state is actually visible, not just
  /// inferred from the fact that this screen is showing at all.
  final AuthUser? signedInUser;

  @override
  State<DeviceDebugScreen> createState() => _DeviceDebugScreenState();
}

class _DeviceDebugScreenState extends State<DeviceDebugScreen> {
  late final Future<DeviceIdentity> _deviceIdentity;
  final _userIdentityService = UserIdentityService();
  final _enrollmentService = EnrollmentService();
  final _tokenVerifier = const TokenVerifier();

  bool _isEnrolling = false;
  String? _enrollError;
  EnrollmentResult? _enrollmentResult;
  VerifiedTokenClaims? _verifiedClaims;

  final _offlineVerifier = const OfflineVerifier();
  bool _isSigningInOffline = false;
  String? _offlineSignInError;
  OfflineVerificationResult? _offlineSignInResult;

  @override
  void initState() {
    super.initState();
    _deviceIdentity = widget.deviceIdentityService.ensureDeviceIdentity().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'Device key generation did not respond in time. On Windows this plugin falls back to '
        'RSA via Windows Hello/TPM, which requires a Windows Hello PIN to be configured on this '
        'machine — this platform is a dev convenience, not the deployment target (Android/iOS).',
      ),
    );
  }

  /// Task 4c — generate this person's per-device keypair, call the `enroll`
  /// mutation (Task 4a) with it and this device's already-established
  /// identity (Task 3), then verify the returned token's signature locally
  /// against the issuer public key baked in at build time (Task 4a). Purely
  /// a debug-view trigger for now, per the story checkpoint's Task 4c scope
  /// -- the real roster/enrollment UI is Task 7.
  Future<void> _enroll(DeviceIdentity deviceIdentity) async {
    final user = widget.signedInUser;
    if (user == null) return;
    setState(() {
      _isEnrolling = true;
      _enrollError = null;
    });
    try {
      final userPubKey = await _userIdentityService.ensureUserKeyPair(user.userId).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'User key generation did not respond in time. On Windows, key creation can trigger a '
          'Windows Hello consent prompt (CredentialUIBroker) with no visible dialog if no Windows '
          'Hello PIN is configured on this machine -- it hangs rather than failing. Same platform '
          'caveat as the device key (see DeviceDebugScreen.initState): a dev convenience, not the '
          'deployment target.',
        ),
      );
      final result = await _enrollmentService.enroll(
        deviceId: deviceIdentity.deviceId,
        devicePubKey: deviceIdentity.publicKeyPem,
        userPubKey: userPubKey,
      );
      final verified = await _tokenVerifier.verify(result.token, issuerPublicKeyPem: issuerPublicKeyPem);
      setState(() {
        _enrollmentResult = result;
        _verifiedClaims = verified;
      });
    } catch (e) {
      setState(() => _enrollError = 'Enrollment failed: $e');
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  /// Task 5 — the actual hard requirement. Runs [OfflineVerifier] against
  /// whatever token is already stored on this device from Task 4c's
  /// enrollment flow -- makes no network call of any kind (see
  /// [OfflineVerifier]'s own doc comment on why that's true by
  /// construction, not just by review). See the story checkpoint's Task 5
  /// entry for exactly what this has and hasn't been demonstrated with on
  /// this particular machine.
  Future<void> _signInOffline(DeviceIdentity deviceIdentity) async {
    final user = widget.signedInUser;
    if (user == null) return;
    setState(() {
      _isSigningInOffline = true;
      _offlineSignInError = null;
      _offlineSignInResult = null;
    });
    try {
      final storedToken = await _enrollmentService.storedToken(user.userId);
      if (storedToken == null) {
        setState(() => _offlineSignInError = 'No enrolled profile found on this device for this person yet — enroll first.');
        return;
      }
      final knownEpoch = await _enrollmentService.knownEpoch(user.userId) ?? 0;

      final result = await _offlineVerifier.verify(
        token: storedToken,
        issuerPublicKeyPem: issuerPublicKeyPem,
        expectedDeviceId: deviceIdentity.deviceId,
        currentKnownEpoch: knownEpoch,
        userPublicKeyPem: await _userIdentityService.ensureUserKeyPair(user.userId).timeout(const Duration(seconds: 15)),
        signChallenge: _productionChallengeSigner(user.userId),
      );
      setState(() => _offlineSignInResult = result);
    } catch (e) {
      setState(() => _offlineSignInError = 'Offline sign-in check failed: $e');
    } finally {
      if (mounted) setState(() => _isSigningInOffline = false);
    }
  }

  /// Not yet verifiable on real hardware in this environment (same
  /// Windows-Hello-PIN gap as Task 4c's user-key generation), so this is
  /// deliberately left unimplemented rather than shipping an unverified
  /// guess: `biometric_signature`'s `createSignature(signatureFormat:
  /// SignatureFormat.raw)` returns "raw signature bytes" without
  /// documenting whether that means DER-encoded or the fixed-width IEEE
  /// P1363 (`r‖s`) format Task 4a's Lambda had to specifically convert
  /// KMS's DER output *into* for JWS compatibility. Guessing wrong here
  /// would silently produce a challenge-response that always fails on
  /// real hardware -- worse than a clearly-flagged gap. See the story
  /// checkpoint's Task 5 entry.
  ChallengeSigner _productionChallengeSigner(String userId) {
    return (nonce) async {
      throw UnimplementedError(
        'Real biometric challenge-response signing is not wired up yet -- see '
        '_productionChallengeSigner\'s doc comment for exactly why, and OfflineVerifier\'s '
        'test suite (test/offline_verifier_test.dart) for the verification logic proven correct '
        'against real ECDSA signatures with a substitute keypair.',
      );
    };
  }

  Widget _buildOfflineSignInSection(DeviceIdentity identity) {
    if (widget.signedInUser == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Offline Sign-In', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Verifies the stored token locally -- signature, expiry, device-id, epoch, and a '
          'challenge-response -- with no network call.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('offlineSignInButton'),
            onPressed: _isSigningInOffline ? null : () => _signInOffline(identity),
            child: _isSigningInOffline
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in offline (verify stored token)'),
          ),
        ),
        if (_offlineSignInError != null) ...[
          const SizedBox(height: 12),
          Text(_offlineSignInError!, key: const Key('offlineSignInError'), style: const TextStyle(color: Colors.orange)),
        ],
        if (_offlineSignInResult != null) ...[
          const SizedBox(height: 16),
          Text(
            _offlineSignInResult!.isValid
                ? 'Result: PASS'
                : 'Result: FAIL (${_offlineSignInResult!.failure!.name})',
            key: const Key('offlineSignInStatus'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _offlineSignInResult!.isValid ? Colors.green : Colors.red,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEnrollmentSection(DeviceIdentity identity) {
    if (widget.signedInUser == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Enrollment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('enrollButton'),
            onPressed: _isEnrolling ? null : () => _enroll(identity),
            child: _isEnrolling
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enroll this device'),
          ),
        ),
        if (_enrollError != null) ...[
          const SizedBox(height: 12),
          Text(_enrollError!, style: const TextStyle(color: Colors.red)),
        ],
        if (_enrollmentResult != null && _verifiedClaims != null) ...[
          const SizedBox(height: 16),
          Text(
            _verifiedClaims!.signatureValid ? 'Signature: VALID' : 'Signature: INVALID',
            key: const Key('enrollmentSignatureStatus'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _verifiedClaims!.signatureValid ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          const Text('Decoded claims:'),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_verifiedClaims!.claims),
            key: const Key('enrollmentClaimsText'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roster Vault — Device Debug')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<DeviceIdentity>(
          future: _deviceIdentity,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Device identity failed: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              );
            }
            final identity = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.signedInUser != null) ...[
                  Text(
                    'Signed in as: ${widget.signedInUser!.username}',
                    key: const Key('signedInUserText'),
                    style: const TextStyle(fontSize: 16, color: Colors.green),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Device identity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (identity == null)
                  const Text('Generating device keypair…')
                else ...[
                  SelectableText('Device ID: ${identity.deviceId}'),
                  const SizedBox(height: 8),
                  const Text('Device public key:'),
                  SelectableText(identity.publicKeyPem, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  _buildEnrollmentSection(identity),
                  _buildOfflineSignInSection(identity),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
