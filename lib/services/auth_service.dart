import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:enterprise_bike_showroom/core/errors/app_exception.dart';
import 'package:enterprise_bike_showroom/core/errors/error_mapper.dart';
import 'package:enterprise_bike_showroom/core/helpers/logger.dart';

/// Supabase Auth wrapper.
///
/// Handles email/password sign in, sign up, reset, refresh and session
/// persistence. The current access token is exposed for interceptors and
/// audit metadata; it is never logged.
class AuthService {
  AuthService();

  /// Broadcast stream of auth state changes (session created/refreshed/
  /// revoked). Listeners are kept minimal and short-lived.
  final StreamController<AuthState> _authChanges =
      StreamController<AuthState>.broadcast();

  StreamSubscription<AuthState>? _subscription;

  /// The Supabase client (initialized in `main.dart`).
  SupabaseClient get client => Supabase.instance.client;

  /// Live auth-state stream.
  Stream<AuthState> get authChanges => _authChanges.stream;

  /// Current session (null when signed out).
  AuthSession? get currentSession => client.auth.currentSession;

  /// Currently authenticated user (null when signed out).
  AuthUser? get currentUser => client.auth.currentSession?.user;

  /// Auth user id (for RLS/audit).
  String? get currentUserId => currentUser?.id;

  /// Current access token (for Authorization headers).
  String? get currentAccessToken => currentSession?.accessToken;

  /// True when a valid session exists.
  bool get hasSession =>
      currentSession != null && currentSession!.accessToken.isNotEmpty;

  /// Starts listening to auth state changes.
  void init() {
    if (_subscription != null) return;
    _subscription = client.auth.onAuthStateChange.listen((AuthState state) {
      AppLogger.info(
        'AUTH',
        'state: ${state.eventName}, user: ${state.session?.user?.id ?? '-'}',
      );
      _authChanges.add(state);
    });
  }

  /// Signs in with email + password.
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final AuthUser? user = response.data.user;
      if (user == null) {
        throw AppAuthException('Sign in failed. Please try again.');
      }
      AppLogger.info('AUTH', 'signed in: ${user.email ?? '-'}');
      return user;
    } on AppAuthException {
      rethrow;
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Creates an account (email confirmation may be required by the project).
  Future<AuthUser> signUp({
    required String email,
    required String password,
    Map<String, String>? data,
  }) async {
    try {
      final AuthResponse response = await client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: data,
      );
      final AuthUser? user = response.data.user;
      if (user == null) {
        throw AppAuthException('Sign up failed. Please try again.');
      }
      AppLogger.info('AUTH', 'signed up: ${user.email ?? '-'}');
      return user;
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Sends a password reset email.
  Future<void> sendPasswordReset(String email) async {
    try {
      await client.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
      );
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Updates the password of the signed-in user.
  Future<void> updatePassword(String newPassword) async {
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw ErrorMapper.map(e);
    }
  }

  /// Signs out the current session on all devices.
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
      AppLogger.info('AUTH', 'signed out');
    } catch (e) {
      AppLogger.warning('AUTH', 'signOut error', error: e);
    }
  }

  /// Refreshes the current session tokens.
  Future<void> refreshSession() async {
    if (!hasSession) return;
    try {
      await client.auth.refreshSession();
    } catch (e) {
      AppLogger.warning('AUTH', 'refreshSession error', error: e);
    }
  }

  /// Disposes listeners.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _authChanges.close();
  }
}
