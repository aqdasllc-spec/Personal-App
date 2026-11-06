import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Who is using the app right now.
sealed class AppSession {
  const AppSession();
}

/// No account: everything stays on this device. Allowed by design (decision D-12).
class LocalOnlySession extends AppSession {
  const LocalOnlySession();
}

class SignedInSession extends AppSession {
  const SignedInSession({required this.userId, required this.email});
  final String userId;
  final String email;
}

class SignedOutSession extends AppSession {
  const SignedOutSession();
}

enum AuthFailureKind { invalidCredentials, emailNotConfirmed, weakPassword, network, rateLimited, unknown }

class AuthFailure implements Exception {
  AuthFailure(this.kind, this.message);
  final AuthFailureKind kind;
  final String message;
  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  AppSession get current;
  Stream<AppSession> get changes;
  Future<void> signIn(String email, String password);

  /// Returns true when the account is created and signed in, false when email confirmation is required first.
  Future<bool> signUp(String email, String password);
  Future<void> signOut();
  Future<void> continueLocalOnly();
}

/// Rules shared by UI validation and tests. Server-side rules still apply.
abstract final class AuthValidation {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(s)) return 'That doesn\'t look like an email address.';
    return null;
  }

  static String? newPassword(String? v) {
    final s = v ?? '';
    if (s.length < 10) return 'Use at least 10 characters.';
    if (s.toLowerCase() == s || !RegExp(r'[0-9]').hasMatch(s)) return 'Mix upper and lower case letters and at least one number.';
    return null;
  }
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {required Future<void> Function() onLocalOnly}) : _onLocalOnly = onLocalOnly {
    _sub = _client.auth.onAuthStateChange.listen((s) => _emit(_map(s.session)));
  }

  final sb.SupabaseClient _client;
  final Future<void> Function() _onLocalOnly;
  final _controller = StreamController<AppSession>.broadcast();
  late final StreamSubscription<sb.AuthState> _sub;
  AppSession? _override;

  static AppSession _map(sb.Session? s) =>
      s == null ? const SignedOutSession() : SignedInSession(userId: s.user.id, email: s.user.email ?? '');

  void _emit(AppSession s) {
    _override = null;
    _controller.add(s);
  }

  @override
  AppSession get current => _override ?? _map(_client.auth.currentSession);

  @override
  Stream<AppSession> get changes => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } on sb.AuthException catch (e) {
      throw _failure(e);
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, 'Can\'t reach the server. Check your connection and try again.');
    }
  }

  @override
  Future<bool> signUp(String email, String password) async {
    try {
      final r = await _client.auth.signUp(email: email.trim(), password: password);
      return r.session != null;
    } on sb.AuthException catch (e) {
      throw _failure(e);
    } catch (e) {
      throw AuthFailure(AuthFailureKind.network, 'Can\'t reach the server. Check your connection and try again.');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> continueLocalOnly() async {
    await _onLocalOnly();
    _override = const LocalOnlySession();
    _controller.add(const LocalOnlySession());
  }

  AuthFailure _failure(sb.AuthException e) {
    final code = e.code ?? '';
    if (code == 'invalid_credentials') return AuthFailure(AuthFailureKind.invalidCredentials, 'Email or password is incorrect.');
    if (code == 'email_not_confirmed') return AuthFailure(AuthFailureKind.emailNotConfirmed, 'Please confirm your email address first - check your inbox.');
    if (code == 'weak_password') return AuthFailure(AuthFailureKind.weakPassword, 'That password is too weak or has appeared in a known data breach.');
    if (code.contains('rate_limit')) return AuthFailure(AuthFailureKind.rateLimited, 'Too many attempts. Wait a minute and try again.');
    return AuthFailure(AuthFailureKind.unknown, e.message);
  }

  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

/// Used when no Supabase project is configured (and in tests): the app runs local-only.
class LocalOnlyAuthRepository implements AuthRepository {
  @override
  AppSession get current => const LocalOnlySession();
  @override
  Stream<AppSession> get changes => const Stream.empty();
  @override
  Future<void> signIn(String email, String password) async =>
      throw AuthFailure(AuthFailureKind.unknown, 'Cloud sync is not configured in this build.');
  @override
  Future<bool> signUp(String email, String password) async =>
      throw AuthFailure(AuthFailureKind.unknown, 'Cloud sync is not configured in this build.');
  @override
  Future<void> signOut() async {}
  @override
  Future<void> continueLocalOnly() async {}
}
