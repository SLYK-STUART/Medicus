import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../viewmodels/auth/auth_viewmodel.dart';

/// Widget-level defense in depth. The router's redirect logic is the
/// primary gate (it decides which screen you land on), but this catches
/// the gap case where a role changes *while a guarded screen is already
/// mounted* — e.g. you edit role in the Supabase dashboard mid-session — and
/// the redirect hasn't fired yet because no navigation event triggered it.
/// RLS policies remain the actual security boundary regardless; this is
/// UX, not access control.
class RoleGuard extends ConsumerWidget {
  const RoleGuard({
    super.key,
    required this.allowedRoles,
    required this.child,
  });

  final List<AppRole> allowedRoles;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile != null && allowedRoles.contains(profile.role)) {
          return child;
        }
        return const _AccessDeniedScreen();
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Error loading profile: $error')),
      ),
    );
  }
}

class _AccessDeniedScreen extends ConsumerWidget {
  const _AccessDeniedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("You don't have access to this page."),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.read(authFormControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}