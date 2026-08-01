import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import '../receptionist/checkin_screen.dart'; // queueRepositoryProvider

class PatientQueueStatusCard extends ConsumerWidget {
  const PatientQueueStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    if (profile == null) return const SizedBox.shrink();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<List<AppointmentModel>>(
      stream: ref.read(appointmentRepositoryProvider).watchPatientAppointments(profile.uid),
      builder: (context, apptSnap) {
        final appts = apptSnap.data ?? [];
        AppointmentModel? active;
        for (final a in appts) {
          if (a.scheduledDate == today && a.status == 'checked_in') {
            active = a;
            break;
          }
        }
        if (active == null) return const SizedBox.shrink();

        return StreamBuilder(
          stream: ref.read(queueRepositoryProvider).watchMyQueueStatus(
            hospitalId: active.hospitalId,
            date: today,
            departmentId: active.departmentId,
            patientId: profile.uid,
          ),
          builder: (context, statusSnap) {
            final entry = statusSnap.data;
            if (statusSnap.hasError) {
              // Surfaced rather than silently hidden — a permission error
              // here means something is genuinely wrong with the rules
              // scoping, not just "no active entry", and should be visible.
              return Card(
                color: AppColors.error.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Queue status unavailable: ${statusSnap.error}', style: const TextStyle(color: AppColors.error)),
                ),
              );
            }
            if (entry == null) return const SizedBox.shrink();

            final position = entry.patientsAhead ?? 0;
            final isNext = position == 0 && entry.status == 'waiting';
            final beingSeen = entry.status == 'called' || entry.status == 'in_consultation';
            final isPaused = entry.status == 'paused';

            return Card(
              color: isPaused
                  ? AppColors.urgent
                  : beingSeen
                      ? AppColors.secondary
                      : AppColors.primary,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                      child: Center(
                        child: Text(
                          '#${entry.tokenNumber}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPaused
                                ? 'Consultation paused'
                                : beingSeen
                                    ? "You're being seen now"
                                    : isNext
                                        ? "You're next!"
                                        : entry.patientsAhead == null
                                            ? 'Checked in — position updating...'
                                            : '$position patient${position == 1 ? '' : 's'} ahead of you',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPaused
                                ? 'Please stay nearby — the doctor will resume shortly'
                                : 'In the live queue · ${entry.priority == 'normal' ? 'Standard' : entry.priority.toUpperCase()}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}