import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

class DoctorHistoryScreen extends ConsumerWidget {
  const DoctorHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    if (profile == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<List<AppointmentModel>>(
      stream: ref.read(appointmentRepositoryProvider).watchDoctorAppointmentHistory(
          doctorId: profile.uid,
        hospitalId: profile.hospitalId!,
      ),
      builder: (context, seenSnap) {
        if (seenSnap.hasError) return Center(child: Text('Error: ${seenSnap.error}'));
        if (!seenSnap.hasData) return const Center(child: CircularProgressIndicator());
        final seen = seenSnap.data!;

        return StreamBuilder<List<AppointmentModel>>(
          stream: ref.read(appointmentRepositoryProvider).watchAppointmentsBookedBy(
            uid: profile.uid,
              hospitalId: profile.hospitalId!,
          ),
          builder: (context, initiatedSnap) {
            final initiated = initiatedSnap.data ?? [];
            final referrals = initiated.where((a) => a.source == 'referral').toList();
            final followUps = initiated.where((a) => a.source == 'follow_up').toList();

            final completedCount = seen.where((a) => a.status == 'completed').length;
            final activeToday = seen.where((a) => a.status == 'checked_in').length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(child: _StatTile(icon: Icons.people_outline, value: '${seen.length}', label: 'Total Patients')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatTile(icon: Icons.check_circle_outline, value: '$completedCount', label: 'Completed')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _StatTile(icon: Icons.call_split, value: '${referrals.length}', label: 'Referrals Made')),
                    const SizedBox(width: 10),
                    Expanded(child: _StatTile(icon: Icons.event_repeat, value: '${followUps.length}', label: 'Follow-ups Set')),
                  ],
                ),
                if (activeToday > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_top, color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Text('$activeToday patient${activeToday == 1 ? '' : 's'} referred to you, awaiting pickup', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ],

                _SectionHeader(title: 'Recent Patients', count: seen.length),
                if (seen.isEmpty)
                  const _EmptyHint(text: 'No patients seen yet')
                else
                  ...seen.take(20).map((a) => _AppointmentRow(appointment: a, isPatientSection: true)),

                _SectionHeader(title: 'Referrals You Made', count: referrals.length),
                if (referrals.isEmpty)
                  const _EmptyHint(text: 'No referrals made yet')
                else
                  ...referrals.map((a) => _AppointmentRow(appointment: a, isPatientSection: false)),

                _SectionHeader(title: 'Follow-ups You Scheduled', count: followUps.length),
                if (followUps.isEmpty)
                  const _EmptyHint(text: 'No follow-ups scheduled yet')
                else
                  ...followUps.map((a) => _AppointmentRow(appointment: a, isPatientSection: false)),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.appointment, required this.isPatientSection});
  final AppointmentModel appointment;
  final bool isPatientSection;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(appointment.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('#${appointment.tokenNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        title: Text('Token #${appointment.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          isPatientSection
              ? '${appointment.scheduledDate} · ${appointment.status}'
              : '${appointment.scheduledDate} · ${appointment.departmentId}',
        ),
      ),
    );
  }
}