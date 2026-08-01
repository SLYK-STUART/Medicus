import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

class MyAppointmentsScreen extends ConsumerWidget {
  const MyAppointmentsScreen({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'booked':
        return 'Upcoming';
      case 'checked_in':
        return 'Checked in';
      case 'completed':
        return 'Completed';
      case 'skipped':
        return 'Skipped';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('My Appointments')),
      body: SafeArea(
        child: StreamBuilder<List<AppointmentModel>>(
          stream: ref.read(appointmentRepositoryProvider).watchPatientAppointments(profile.uid),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error: ${snap.error}')));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final appts = snap.data!;
            if (appts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_note_outlined, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('No appointments yet', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Book one from the home screen', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: appts.length,
              itemBuilder: (context, i) {
                final a = appts[i];
                final color = statusColor(a.status);
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: a.status == 'booked' ? () => context.push('/patient/appointment-qr', extra: a) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
                            child: Center(
                              child: Text('#${a.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.scheduledDate, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  a.doctorId == null ? 'Doctor: assigned when called' : 'Doctor assigned',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          if (a.status == 'booked') const Icon(Icons.qr_code, color: AppColors.primary, size: 20),
                          if (a.status == 'booked') const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text(_statusLabel(a.status), style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}