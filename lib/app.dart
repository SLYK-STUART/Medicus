import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // needed for ChangeNotifierProvider on Riverpod 3.x
import 'package:go_router/go_router.dart';
import 'package:hospital_queue_app/views/admin/department_create_screen.dart';
import 'package:hospital_queue_app/views/admin/doctor_list_screen.dart';
import 'package:hospital_queue_app/views/admin/skip_rejoin_policy_screen.dart';
import 'package:hospital_queue_app/views/admin/staff_create_screen.dart';
import 'package:hospital_queue_app/views/doctor/doctor_dashboard.dart';
import 'package:hospital_queue_app/views/patient/appointment_qr_screen.dart';
import 'package:hospital_queue_app/views/patient/booking_screen.dart';
import 'package:hospital_queue_app/views/patient/date_time_confirm_screen.dart';
import 'package:hospital_queue_app/views/patient/live_queue_tracking_screen.dart';
import 'package:hospital_queue_app/views/patient/my_appointments_screen.dart';
import 'package:hospital_queue_app/views/patient/notifications_screen.dart';
import 'package:hospital_queue_app/views/receptionist/checkin_screen.dart';
import 'package:hospital_queue_app/views/receptionist/priority_checkin_screen.dart';
import 'package:hospital_queue_app/views/receptionist/qr_scan_screen.dart';
import 'package:hospital_queue_app/views/receptionist/receptionist_notifications_screen.dart';
import 'package:hospital_queue_app/views/receptionist/skipped_patients_screen.dart';
import 'package:hospital_queue_app/views/receptionist/token_search_screen.dart';
import 'package:hospital_queue_app/views/receptionist/walk_in_booking_screen.dart';
import 'package:hospital_queue_app/views/super_admin/hospital_admin_create_screen.dart';
import 'package:hospital_queue_app/views/super_admin/hospital_create_screen.dart';

import 'core/theme/app_theme.dart';
import 'models/appointment_model.dart';
import 'models/user_model.dart';
import 'router/router_refresh_notifier.dart';
import 'router/splash_gate.dart'; // adjust path to wherever you placed splash_gate.dart
import 'services/push_notification_service.dart';
import 'viewmodels/auth/auth_viewmodel.dart';
import 'views/admin/hospital_admin_home_screen.dart';
import 'views/auth/login_screen.dart';
import 'views/auth/signup_screen.dart';
import 'views/patient/patient_home_screen.dart';
import 'views/receptionist/receptionist_home_screen.dart';
import 'views/splash_screen.dart';
import 'views/super_admin/super_admin_home_screen.dart';

String _basePathForRole(AppRole role) {
  switch (role) {
    case AppRole.patient:
      return '/patient';
    case AppRole.receptionist:
      return '/receptionist';
    case AppRole.doctor:
      return '/doctor';
    case AppRole.hospitalAdmin:
      return '/admin';
    case AppRole.superAdmin:
      return '/super-admin';
  }
}

String _homePathForRole(AppRole role) => '${_basePathForRole(role)}/home';

/// Gates the splash screen so it's shown for a minimum duration even if
/// auth/profile resolution completes almost instantly (e.g. cached
/// Supabase session on a warm start). See splash_gate.dart.
final splashGateProvider = ChangeNotifierProvider<SplashGate>((ref) {
  return SplashGate();
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(routerRefreshNotifierProvider);
  final splashGate = ref.watch(splashGateProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([refreshNotifier, splashGate]),
    redirect: (context, state) {
      final path = state.matchedLocation;
      debugPrint('[router] redirect check for $path, currentUser=${ref.read(authStateChangesProvider).value?.id}');
      final isAuthRoute = path == '/login' || path == '/signup';
      final isSplash = path == '/splash';

      // Hold on splash until the minimum duration has elapsed, no matter
      // how fast auth/profile resolve. This must be checked before any
      // auth/profile logic below, since a cached session can resolve
      // before the splash screen paints a single frame.
      if (!splashGate.elapsed) {
        return isSplash ? null : '/splash';
      }

      final authAsync = ref.read(authStateChangesProvider);

      // Still resolving whether anyone is signed in at all.
      if (authAsync.isLoading) {
        return isSplash ? null : '/splash';
      }

      final authUser = authAsync.value;
      if (authUser == null) {
        return isAuthRoute ? null : '/login';
      }

      // Signed in — resolve role/hospitalId from Supabase profiles.
      final profileAsync = ref.read(currentUserProfileProvider);
      if (profileAsync.isLoading) {
        return isSplash ? null : '/splash';
      }

      final profile = profileAsync.value;
      if (profile == null) {
        // Auth account exists but profiles row doesn't — orphaned account
        // or profile was deleted. Can't route by role with nothing to use.
        return '/login';
      }

      final basePath = _basePathForRole(profile.role);
      final homePath = '$basePath/home';

      if (isAuthRoute || isSplash) return homePath;

      // Signed in but sitting on a path outside their role's area — e.g.
      // typed a URL directly, or their role changed mid-session and
      // refreshListenable just fired.
      if (!path.startsWith(basePath)) return homePath;

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/patient/home', builder: (context, state) => const PatientHomeScreen()),
      GoRoute(path: '/receptionist/home', builder: (context, state) => const ReceptionistHomeScreen()),
      GoRoute(path: '/doctor/home', builder: (context, state) => const DoctorDashboardScreen()),
      GoRoute(path: '/admin/home', builder: (context, state) => const HospitalAdminHomeScreen()),
      GoRoute(path: '/super-admin/home', builder: (context, state) => const SuperAdminHomeScreen()),
      GoRoute(path: '/super-admin/hospitals/create', builder: (context, state) => const HospitalCreateScreen()),
      GoRoute(path: '/super-admin/staff/create-hospital-admin', builder: (context, state) => const HospitalAdminCreateScreen()),
      GoRoute(path: '/admin/staff/create', builder: (context, state) => const StaffCreateScreen()),
      GoRoute(path: '/patient/book', builder: (context, state) => const BookingScreen()),
      GoRoute(path: '/patient/appointments', builder: (context, state) => const MyAppointmentsScreen()),
      GoRoute(path: '/receptionist/checkin', builder: (context, state) => const CheckInScreen()),
      GoRoute(path: '/admin/departments', builder: (context, state) => const DepartmentCreateScreen()),
      GoRoute(path: '/patient/notifications', builder: (context, state) => const NotificationsScreen()),
      GoRoute(path: '/receptionist/priority-checkin', builder: (context, state) => const PriorityCheckInScreen()),
      GoRoute(path: '/admin/skip-policy', builder: (context, state) => const SkipPolicyScreen()),
      GoRoute(path: '/receptionist/skipped', builder: (context, state) => const SkippedPatientsScreen()),
      GoRoute(path: '/receptionist/walkin-booking', builder: (context, state) => const WalkInBookingScreen()),
      GoRoute(path: '/admin/doctors', builder: (context, state) => const DoctorListScreen()),
      GoRoute(path: '/receptionist/search', builder: (context, state) => const TokenSearchScreen()),
      GoRoute(path: '/receptionist/scan', builder: (context, state) => const QrScanScreen()),
      GoRoute(path: '/receptionist/notifications', builder: (context, state) => const ReceptionistNotificationsScreen()),
      GoRoute(
        path: '/patient/appointment-qr',
        builder: (context, state) => AppointmentQrScreen(appointment: state.extra as AppointmentModel),
      ),
      GoRoute(
        path: '/patient/book/date-time',
        builder: (context, state) {
          final data = state.extra as Map<String, String>;
          return DateTimeConfirmScreen(
            hospitalId: data['hospitalId']!,
            hospitalName: data['hospitalName']!,
            departmentId: data['departmentId']!,
            departmentName: data['departmentName']!,
          );
        },
      ),
      GoRoute(
        path: '/patient/queue-tracking',
        builder: (context, state) => const LiveQueueTrackingScreen(),
      ),
    ],
  );
});

class HospitalQueueApp extends ConsumerWidget {
  const HospitalQueueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // System tray push for every signed-in role (patient, staff, admins).
    ref.listen(authStateChangesProvider, (prev, next) {
      final user = next.value;
      if (user != null) {
        PushNotificationService.instance.startForUser(user.id);
      } else {
        PushNotificationService.instance.stop();
      }
    });
    final existingUser = ref.read(authStateChangesProvider).value;
    if (existingUser != null) {
      PushNotificationService.instance.startForUser(existingUser.id);
    }

    return MaterialApp.router(
      title: 'Medicare',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      routerConfig: router,
    );
  }
}