import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../repositories/doctor_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import 'current_patient_screen.dart';
import 'doctor_history_screen.dart';
import 'live_queue_screen.dart';

final _doctorRepoProvider = Provider((ref) => DoctorRepository());

// Height of the floating pill (64) + its bottom margin (12) — used to
// reserve matching space at the bottom of every tab's content so nothing
// renders behind the nav bar. Defined once, referenced by both the nav
// bar itself and the content padding below, so they can't drift apart.
const double _navBarHeight = 64;
const double _navBarBottomMargin = 12;

class DoctorDashboardScreen extends ConsumerStatefulWidget {
  const DoctorDashboardScreen({super.key});
  @override
  ConsumerState<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends ConsumerState<DoctorDashboardScreen> {
  int _tabIndex = 0;

  static const _titles = ['Today\'s Queue', 'Current Patient', 'History', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;

    if (profile == null || hospitalId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder(
      stream: ref.read(_doctorRepoProvider).watchMyDoctorProfile(profile.uid),
      builder: (context, doctorSnap) {
        final doctor = doctorSnap.data;
        if (doctor == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final systemInset = MediaQuery.of(context).padding.bottom;
        final reservedBottomSpace = _navBarHeight + _navBarBottomMargin + systemInset;

        return Scaffold(
          backgroundColor: AppColors.surface,
          extendBody: true,
          appBar: AppBar(title: Text(_titles[_tabIndex])),
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: reservedBottomSpace),
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  const LiveQueueBody(),
                  CurrentPatientScreen(hospitalId: hospitalId, doctor: doctor),
                  const DoctorHistoryScreen(),
                  _SettingsTab(doctor: doctor),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _FloatingNavBar(
            currentIndex: _tabIndex,
            onTap: (i) => setState(() => _tabIndex = i),
          ),
        );
      },
    );
  }
}

/// A floating, pill-shaped bottom navigation bar. Rather than a flat bar
/// docked to the screen edge, it sits above the content with margin on
/// all sides and a soft shadow, with a sliding highlight capsule behind
/// the active item.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.groups_rounded, label: 'Queue'),
    (icon: Icons.assignment_ind_rounded, label: 'Patient'),
    (icon: Icons.history_rounded, label: 'History'),
    (icon: Icons.tune_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final systemInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, systemInset + _navBarBottomMargin),
      child: Container(
        height: _navBarHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / _items.length;

            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: itemWidth * currentIndex,
                  top: 8,
                  bottom: 8,
                  width: itemWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(_items.length, (i) {
                    final selected = i == currentIndex;
                    final item = _items[i];
                    return Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => onTap(i),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? Colors.white : AppColors.textSecondary,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                item.icon,
                                size: 22,
                                color: selected ? Colors.white : AppColors.textSecondary,
                              ),
                              const SizedBox(height: 3),
                              Text(item.label),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab({required this.doctor});
  final dynamic doctor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bottom padding trimmed from 100 to 24 — the dashboard now reserves
    // space for the nav bar centrally (see reservedBottomSpace above), so
    // this tab no longer needs its own oversized manual allowance.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Card(child: ListTile(leading: const Icon(Icons.category_outlined), title: const Text('Department'), subtitle: Text(doctor.departmentId), trailing: const Text('Admin-managed', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)))),
        Card(child: ListTile(leading: const Icon(Icons.meeting_room_outlined), title: const Text('Room'), subtitle: Text(doctor.roomNumber ?? 'Not set'), trailing: const Text('Admin-managed', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)))),
        Card(child: ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Avg. Consultation'), subtitle: Text('${doctor.avgConsultationMinutes} min · auto-calculated'))),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          icon: const Icon(Icons.logout),
          label: const Text('Sign Out'),
          onPressed: () => ref.read(authFormControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}