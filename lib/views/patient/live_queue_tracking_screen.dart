import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import '../receptionist/checkin_screen.dart'; // queueRepositoryProvider

class LiveQueueTrackingScreen extends ConsumerWidget {
  const LiveQueueTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Live Queue')),
      body: SafeArea(
        child: StreamBuilder<List<AppointmentModel>>(
          stream: ref.read(appointmentRepositoryProvider).watchPatientAppointments(profile.uid),
          builder: (context, apptSnap) {
            if (apptSnap.hasError) return Center(child: Text('Error: ${apptSnap.error}'));
            if (!apptSnap.hasData) return const Center(child: CircularProgressIndicator());

            AppointmentModel? active;
            for (final a in apptSnap.data!) {
              if (a.scheduledDate == today && a.status == 'checked_in') {
                active = a;
                break;
              }
            }

            if (active == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('Not checked in yet', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      const Text('Live tracking starts once reception checks you in'),
                    ],
                  ),
                ),
              );
            }

            final activeAppointment = active;

            return StreamBuilder(
              stream: ref.read(queueRepositoryProvider).watchMyQueueStatus(
                hospitalId: activeAppointment.hospitalId,
                date: today,
                departmentId: activeAppointment.departmentId,
                patientId: profile.uid,
              ),
              builder: (context, statusSnap) {
                if (statusSnap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Card(
                      color: AppColors.error.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Queue status unavailable: ${statusSnap.error}', style: const TextStyle(color: AppColors.error)),
                      ),
                    ),
                  );
                }

                final entry = statusSnap.data;
                if (statusSnap.connectionState == ConnectionState.waiting && !statusSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (entry == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_empty, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text('No active queue entry', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          const Text('Your live status will appear once you are in the queue'),
                        ],
                      ),
                    ),
                  );
                }

                final position = entry.patientsAhead ?? 0;
                final isNext = position == 0 && entry.status == 'waiting';
                final beingSeen = entry.status == 'called' || entry.status == 'in_consultation';
                final isPaused = entry.status == 'paused';
                final headerColor = isPaused
                    ? AppColors.urgent
                    : beingSeen
                        ? AppColors.secondary
                        : AppColors.primary;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: headerColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isPaused ? 'Status' : 'Your Token',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const Spacer(),
                              if (!beingSeen && !isPaused) const Text('Position', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('#${entry.tokenNumber}', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
                              const Spacer(),
                              if (!beingSeen && !isPaused)
                                Text(
                                  isNext ? 'Next' : _ordinal(position + 1),
                                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                                ),
                              if (isPaused)
                                const Text(
                                  'Paused',
                                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          Icon(
                            isPaused
                                ? Icons.pause_circle_outline
                                : beingSeen
                                    ? Icons.meeting_room_outlined
                                    : Icons.groups_outlined,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isPaused
                                  ? 'Consultation paused — please stay nearby. The doctor will resume shortly.'
                                  : beingSeen
                                      ? "You're being seen now"
                                      : isNext
                                          ? "You're next!"
                                          : entry.patientsAhead == null
                                              ? 'Checked in — position updating...'
                                              : '$position patient${position == 1 ? '' : 's'} ahead of you',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.priority_high, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Text('Priority: ${entry.priority == 'normal' ? 'Standard' : entry.priority.toUpperCase()}'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }
}