import 'package:flutter/material.dart';

import 'services/device_identity_service.dart';

void main() {
  runApp(const RosterVaultApp());
}

class RosterVaultApp extends StatelessWidget {
  const RosterVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Vault',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: DeviceDebugScreen(deviceIdentityService: DeviceIdentityService()),
    );
  }
}

/// Development-only screen. Shows this device's identity material so it can
/// be inspected during Task 3 (device keypair generation) and beyond.
/// Never shown in a release build's normal flow — the real entry point is
/// the roster screen (Task 7).
class DeviceDebugScreen extends StatefulWidget {
  const DeviceDebugScreen({super.key, required this.deviceIdentityService});

  final DeviceIdentityService deviceIdentityService;

  @override
  State<DeviceDebugScreen> createState() => _DeviceDebugScreenState();
}

class _DeviceDebugScreenState extends State<DeviceDebugScreen> {
  late final Future<DeviceIdentity> _deviceIdentity;

  @override
  void initState() {
    super.initState();
    _deviceIdentity = widget.deviceIdentityService.ensureDeviceIdentity();
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
