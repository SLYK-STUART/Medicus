import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/user_model.dart';

class AuthRepository {
  AuthRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// Emits the current auth user (or null) on every session change.
  Stream<User?> authStateChanges() {
    return _client.auth.onAuthStateChange.map((event) => event.session?.user);
  }

  User? get currentUser => _client.auth.currentUser;

  /// Self-service signup always creates a `patient`. Staff accounts are
  /// created later via service-role Edge Functions, never here.
  Future<UserModel> signUp({
    required String email,
    required String password,
    String? displayName,
    String? phoneNumber,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          if (displayName != null && displayName.isNotEmpty) 'display_name': displayName,
          if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
        },
      );

      final user = response.user;
      if (user == null) {
        // Common when email confirmation is required and the session is withheld.
        throw const AuthFailure(
          'Sign up succeeded but no session was returned. '
          'If email confirmation is enabled in Supabase Auth settings, '
          'confirm the email (or disable confirmations for development) and sign in.',
          code: 'no-session',
        );
      }

      final userModel = UserModel(
        uid: user.id,
        email: email,
        displayName: displayName,
        phoneNumber: phoneNumber,
        role: AppRole.patient,
        hospitalId: null,
      );

      try {
        await _client.from('profiles').insert(userModel.toProfileInsert());
      } catch (e) {
        // Auth user exists but profile write failed — sign out so the app
        // doesn't treat this as a logged-in patient with no profile.
        // Client cannot delete the auth user (needs service role); call out
        // in Step 2 notes as a known orphan risk to clean via dashboard.
        await _client.auth.signOut();
        throw DataFailure(
          'Account created but profile setup failed: $e. '
          'Signed out — if the email is already taken on retry, delete the '
          'orphan user in Supabase Auth dashboard.',
          code: 'profile-insert-failed',
        );
      }

      return userModel;
    } on AuthFailure {
      rethrow;
    } on DataFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFailure(e.message, code: e.statusCode);
    } catch (e) {
      throw AuthFailure(e.toString(), code: 'sign-up-failed');
    }
  }

  Future<UserModel> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final uid = response.user?.id;
      if (uid == null) {
        throw const AuthFailure('Sign in returned no user.', code: 'no-user');
      }

      final profile = await fetchUserProfile(uid);
      if (profile == null) {
        throw const AuthFailure(
          'Signed in but no matching profiles row was found.',
          code: 'missing-profile',
        );
      }
      return profile;
    } on AuthFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFailure(e.message, code: e.statusCode);
    } catch (e) {
      throw AuthFailure(e.toString(), code: 'sign-in-failed');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<UserModel?> fetchUserProfile(String uid) async {
    try {
      final data = await _client.from('profiles').select().eq('id', uid).maybeSingle();
      if (data == null) return null;
      return UserModel.fromSupabase(data);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  /// Live profile stream via Realtime. Requires `profiles` in
  /// `supabase_realtime` publication (see migration 20260722130000).
  Stream<UserModel?> watchUserProfile(String uid) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((rows) {
      if (rows.isEmpty) return null;
      return UserModel.fromSupabase(rows.first);
    });
  }
}
