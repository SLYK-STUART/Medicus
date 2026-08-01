import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/notification_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import '../patient/notifications_screen.dart'; // notificationRepositoryProvider

class ReceptionistHomeScreen extends ConsumerWidget {
  const ReceptionistHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${profile?.displayName?.split(' ').first ?? 'there'}'),
        actions: [
          if (profile != null)
            StreamBuilder<List<NotificationModel>>(
              stream: ref.read(notificationRepositoryProvider).watchMyNotifications(profile.uid),
              builder: (context, snap) {
                final unread = (snap.data ?? []).where((n) => !n.read).length;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none),
                      onPressed: () => context.push('/receptionist/notifications'),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text('$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authFormControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: hospitalId == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            StreamBuilder<Map<String, int>>(
              stream: ref.read(appointmentRepositoryProvider).watchTodaysStatsForHospital(
                hospitalId: hospitalId,
                date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
              ),
              builder: (context, snap) {
                final stats = snap.data ?? {'booked': 0, 'checked_in': 0, 'completed': 0, 'skipped': 0};
                return Row(
                  children: [
                    Expanded(child: _StatCard(icon: Icons.event_available, value: '${stats['booked']}', label: 'Booked')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(icon: Icons.how_to_reg, value: '${stats['checked_in']}', label: 'Checked in')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(icon: Icons.warning_amber, value: '${stats['skipped']}', label: 'Skipped')),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            _ActionCard(
              icon: Icons.qr_code_scanner,
              color: AppColors.primary,
              title: 'Scan QR to Check In',
              subtitle: 'Fastest check-in method',
              onTap: () => context.push('/receptionist/scan'),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.how_to_reg,
              color: AppColors.primary,
              title: "Today's Check-Ins",
              subtitle: 'View booked and checked-in patients',
              onTap: () => context.push('/receptionist/checkin'),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.tag,
              color: AppColors.primary,
              title: 'Find Patient',
              subtitle: 'Search by token number or name',
              onTap: () => context.push('/receptionist/search'),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.emergency,
              color: AppColors.critical,
              title: 'Priority Check-In',
              subtitle: 'Emergency walk-in or escalate a waiting patient',
              onTap: () => context.push('/receptionist/priority-checkin'),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.person_add,
              color: AppColors.secondary,
              title: 'Book Walk-In Patient',
              subtitle: 'For patients without a smartphone',
              onTap: () => context.push('/receptionist/walkin-booking'),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.replay,
              color: AppColors.urgent,
              title: 'Skipped Patients',
              subtitle: 'Rejoin patients the doctor couldn\'t see',
              onTap: () => context.push('/receptionist/skipped'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}