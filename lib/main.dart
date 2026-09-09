import 'dart:async';
import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'screens/login_screen.dart';
import 'services/device_identity_service.dart';

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
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
