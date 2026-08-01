import 'package:flutter/foundation.dart';

/// Ensures the splash screen is shown for at least [minDuration], even if
/// auth/profile resolution completes almost instantly (e.g. cached
/// Gates the splash screen for a minimum duration even if auth/profile
/// resolution completes almost instantly (e.g. cached Supabase session on
/// a warm start). Without this, GoRouter's
/// redirect can fire before the splash animation renders a single frame.
class SplashGate extends ChangeNotifier {
  SplashGate({this.minDuration = const Duration(milliseconds: 5000)}) {
    Future.delayed(minDuration, () {
      _elapsed = true;
      notifyListeners();
    });
  }

  final Duration minDuration;
  bool _elapsed = false;

  /// True once [minDuration] has passed since this gate was created.
  bool get elapsed => _elapsed;
}