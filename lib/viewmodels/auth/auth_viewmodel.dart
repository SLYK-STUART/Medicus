import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_model.dart';
import '../../repositories/auth_repository.dart';
import '../../core/supabase/supabase_init.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => supabase);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(client: ref.watch(supabaseClientProvider));
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.id;
  if (uid == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchUserProfile(uid);
});

class AuthFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signIn(email: email, password: password);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    String? displayName,
    String? phoneNumber,
  }) async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signUp(
            email: email,
            password: password,
            displayName: displayName,
            phoneNumber: phoneNumber,
          );
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<void> signOut() async => ref.read(authRepositoryProvider).signOut();
}

final authFormControllerProvider = AsyncNotifierProvider<AuthFormController, void>(AuthFormController.new);
