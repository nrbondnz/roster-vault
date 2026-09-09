import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Task 4c — calls the `enroll` mutation (Task 4a) with this device's and
/// this person's public keys, plus the live Cognito ID token from the
/// session Task 4b's login screen established. Not the typed `amplify_api`
/// client: the enrollment API is a custom AppSync endpoint outside
/// Amplify's `data` category (see amplify/backend.ts's own comment on
/// this), so it's called as a plain authenticated HTTPS GraphQL POST.
class EnrollmentResult {
  const EnrollmentResult({required this.token, required this.epoch, required this.expiresAt});

  final String token;
  final int epoch;
  final int expiresAt;
}

class EnrollmentService {
  EnrollmentService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static String _tokenStorageKeyFor(String userId) => 'roster_vault_enrollment_token_$userId';

  Future<EnrollmentResult> enroll({
    required String deviceId,
    required String devicePubKey,
    required String userPubKey,
  }) async {
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    final idToken = session.userPoolTokensResult.value.idToken.raw;
    final userId = session.userSubResult.value;

    final apiUrl = await _enrollApiUrl();

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json', 'Authorization': idToken},
      body: jsonEncode({
        'query': 'mutation Enroll(\$deviceId: String!, \$devicePubKey: String!, \$userPubKey: String!) '
            '{ enroll(deviceId: \$deviceId, devicePubKey: \$devicePubKey, userPubKey: \$userPubKey) '
            '{ token epoch expiresAt } }',
        'variables': {'deviceId': deviceId, 'devicePubKey': devicePubKey, 'userPubKey': userPubKey},
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['errors'] != null) {
      throw StateError('enroll mutation failed: ${body['errors']}');
    }
    final data = body['data']['enroll'] as Map<String, dynamic>;
    final result = EnrollmentResult(
      token: data['token'] as String,
      epoch: data['epoch'] as int,
      expiresAt: data['expiresAt'] as int,
    );

    // Placeholder storage per the Task 4 scoping decision (story
    // checkpoint): OS-level flutter_secure_storage encryption only. PIN-
    // derived wrapping is Task 6's scope, layered on top of this later.
    await _secureStorage.write(key: _tokenStorageKeyFor(userId), value: result.token);

    return result;
  }

  /// The most recently stored token for this user, if enrollment has
  /// already happened this session (or in a previous one).
  Future<String?> storedToken(String userId) => _secureStorage.read(key: _tokenStorageKeyFor(userId));

  Future<String> _enrollApiUrl() async {
    final configJson = await rootBundle.loadString('amplify_outputs.json');
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final custom = config['custom'] as Map<String, dynamic>;
    return custom['enrollApiUrl'] as String;
  }
}
