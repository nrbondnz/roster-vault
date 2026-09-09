import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

/// Task 4b — the one online step in the whole system
/// (docs/roster-vault/Architecture/Enrollment Flow.md step 1). Plain
/// Cognito email/password sign-in against the deployed User Pool; nothing
/// offline-specific happens here. Enrollment itself (calling the `enroll`
/// mutation from Task 4a with this session's ID token) is Task 4c.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final void Function(AuthUser user) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final result = await Amplify.Auth.signIn(
        username: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!result.isSignedIn) {
        setState(() => _errorText = 'Sign-in did not complete: ${result.nextStep.signInStep}');
        return;
      }
      final user = await Amplify.Auth.getCurrentUser();
      widget.onSignedIn(user);
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roster Vault — Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('loginEmailField'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('loginPasswordField'),
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('loginSubmitButton'),
              onPressed: _isSubmitting ? null : _signIn,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign In'),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
