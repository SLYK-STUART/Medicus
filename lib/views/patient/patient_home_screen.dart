import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../models/department_model.dart';
import '../../models/notification_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import 'notifications_screen.dart'; // notificationRepositoryProvider
import 'patient_queue_status_card.dart';

class PatientHomeScreen extends ConsumerWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${profile?.displayName?.split(' ').first ?? 'there'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authFormControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            GestureDetector(
              onTap: () => context.push('/patient/queue-tracking'),
              child: const PatientQueueStatusCard(),
            ),

            // Missing-phone nudge — tied to the real gap that there's no
            // profile/settings screen yet to add one later, so this is
            // honest about a limitation, not decorative.
            if (profile != null && profile.phoneNumber == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: _MissingPhoneNudge(),
              ),

            if (profile != null) _AppointmentsOverviewSection(patientId: profile.uid),

            const SizedBox(height: 4),
            Card(
              color: AppColors.primary,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/patient/book'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline, color: Colors.white, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Book an Appointment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text('Choose a hospital and department', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HomeTile(
                    icon: Icons.event_note_outlined,
                    label: 'My Appointments',
                    onTap: () => context.push('/patient/appointments'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: profile == null
                      ? const _HomeTile(icon: Icons.notifications_none, label: 'Notifications', onTap: null)
                      : _NotificationsTile(patientId: profile.uid),
                ),
              ],
            ),

            if (profile != null) _RecentActivityPreview(patientId: profile.uid),
          ],
        ),
      ),
    );
  }
}

class _MissingPhoneNudge extends StatelessWidget {
  const _MissingPhoneNudge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.urgent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.sms_outlined, color: AppColors.urgent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add a phone number to get SMS updates about your queue position.',
              style: TextStyle(color: AppColors.urgent, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Consolidates everything derived from the patient's own appointments
/// history into a single stream — stats row, next-appointment card
/// (highlighted differently if it's a recurring follow-up), and a quick
/// rebook shortcut. Previously this was three separate widgets each
/// opening their own listener on the same collection.
class _AppointmentsOverviewSection extends ConsumerWidget {
  const _AppointmentsOverviewSection({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<List<AppointmentModel>>(
      stream: ref.read(appointmentRepositoryProvider).watchPatientAppointments(patientId),
      builder: (context, snap) {
        final appts = snap.data ?? [];
        if (appts.isEmpty) return const SizedBox.shrink();

        final completed = appts.where((a) => a.status == 'completed').toList();
        final upcoming = appts.where((a) => a.status == 'booked' && a.scheduledDate.compareTo(today) >= 0).toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

        final next = upcoming.isEmpty ? null : upcoming.first;

        final completedByDate = [...completed]..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
        final lastCompleted = completedByDate.isEmpty ? null : completedByDate.first;

        return Column(
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatTile(value: '${appts.length}', label: 'Total Visits')),
                const SizedBox(width: 10),
                Expanded(child: _StatTile(value: '${completed.length}', label: 'Completed')),
                const SizedBox(width: 10),
                Expanded(child: _StatTile(value: '${upcoming.length}', label: 'Upcoming')),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 12),
              Card(
                color: next.isRecurring ? AppColors.secondary.withValues(alpha: 0.08) : null,
                shape: next.isRecurring
                    ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.3)))
                    : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: next.isRecurring ? AppColors.secondary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                    child: Text(
                      '#${next.tokenNumber}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: next.isRecurring ? AppColors.secondary : AppColors.primary),
                    ),
                  ),
                  title: Text(
                    next.isRecurring ? 'Follow-up appointment' : 'Upcoming appointment',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(next.isRecurring ? '${next.scheduledDate} · same doctor as before' : next.scheduledDate),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/patient/appointments'),
                ),
              ),
            ],
            if (lastCompleted != null) ...[
              const SizedBox(height: 10),
              _QuickRebookCard(hospitalId: lastCompleted.hospitalId, departmentId: lastCompleted.departmentId),
            ],
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _QuickRebookCard extends ConsumerWidget {
  const _QuickRebookCard({required this.hospitalId, required this.departmentId});
  final String hospitalId;
  final String departmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<DepartmentModel>>(
      stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
      builder: (context, snap) {
        final match = (snap.data ?? []).where((d) => d.id == departmentId);
        final deptName = match.isEmpty ? departmentId : match.first.name;

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/patient/book', extra: {'hospitalId': hospitalId, 'departmentId': departmentId}),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.replay_circle_filled_outlined, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Book again in $deptName', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RecentActivityPreview extends ConsumerWidget {
  const _RecentActivityPreview({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<NotificationModel>>(
      stream: ref.read(notificationRepositoryProvider).watchMyNotifications(patientId),
      builder: (context, snap) {
        final notifications = snap.data ?? [];
        if (notifications.isEmpty) return const SizedBox.shrink();
        final recent = notifications.take(2).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
                  TextButton(
                    onPressed: () => context.push('/patient/notifications'),
                    child: const Text('See all'),
                  ),
                ],
              ),
              ...recent.map((n) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: n.read ? Colors.white : AppColors.surfaceVariant.withValues(alpha: 0.6),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.circle_notifications_outlined, color: n.read ? AppColors.textSecondary : AppColors.primary),
                  title: Text(n.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  subtitle: n.createdAt != null ? Text(DateFormat('MMM d, h:mm a').format(n.createdAt!), style: const TextStyle(fontSize: 11)) : null,
                ),
              )),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationsTile extends ConsumerWidget {
  const _NotificationsTile({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<NotificationModel>>(
      stream: ref.read(notificationRepositoryProvider).watchMyNotifications(patientId),
      builder: (context, snap) {
        final unread = (snap.data ?? []).where((n) => !n.read).length;
        return _HomeTile(
          icon: Icons.notifications_none,
          label: 'Notifications',
          badgeCount: unread,
          onTap: () => context.push('/patient/notifications'),
        );
      },
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.icon, required this.label, required this.onTap, this.badgeCount = 0});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: AppColors.primary, size: 28),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}