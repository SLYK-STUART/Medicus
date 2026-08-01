import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewmodels/auth/auth_viewmodel.dart';

/// GoRouter's `redirect` callback doesn't automatically re-run when a
/// Riverpod stream emits — it only re-evaluates on navigation events unless
/// given a Listenable via `refreshListenable`. This bridges the two:
/// whenever auth state or the live user profile changes, it notifies
/// GoRouter to re-run redirect logic (e.g. so editing `role` in Supabase
/// bounces the user to the right home screen without a manual navigation).
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(this._ref) {
    _ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    _ref.listen(currentUserProfileProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}

final routerRefreshNotifierProvider = Provider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});