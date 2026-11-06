import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/tokens.dart';
import 'auth_repository.dart';

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});
  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false, _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      if (_creating) {
        final signedIn = await repo.signUp(_email.text, _password.text);
        if (!signedIn && mounted) {
          setState(
            () => _info = 'Account created. Check your inbox to confirm your email, then sign in.',
          );
        }
      } else {
        await repo.signIn(_email.text, _password.text);
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Folio', style: t.displaySmall),
                  const SizedBox(height: Space.s8),
                  Text(
                    _creating ? 'Create your account' : 'Welcome back',
                    style: t.bodyLarge?.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: Space.s32),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: AuthValidation.email,
                  ),
                  const SizedBox(height: Space.s16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [
                      _creating
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => _creating
                        ? AuthValidation.newPassword(v)
                        : ((v ?? '').isEmpty ? 'Enter your password.' : null),
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.s12),
                    Text(
                      _error!,
                      style: t.bodyMedium?.copyWith(color: c.danger),
                      semanticsLabel: 'Error: $_error',
                    ),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: Space.s12),
                    Text(_info!, style: t.bodyMedium),
                  ],
                  const SizedBox(height: Space.s24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? 'Please wait…'
                          : (_creating ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: Space.s8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                            _info = null;
                          }),
                    child: Text(
                      _creating
                          ? 'I already have an account'
                          : 'Create an account',
                    ),
                  ),
                  const Divider(height: Space.s32),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => ref
                              .read(authRepositoryProvider)
                              .continueLocalOnly(),
                    child: const Text('Use without an account'),
                  ),
                  const SizedBox(height: Space.s8),
                  Text(
                    'Without an account everything stays on this device and is not synced or backed up to the cloud.',
                    style: t.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
