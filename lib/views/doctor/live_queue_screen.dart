import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/queue_entry_model.dart';
import '../../repositories/doctor_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../receptionist/checkin_screen.dart'; // queueRepositoryProvider

final _doctorRepoProvider = Provider((ref) => DoctorRepository());

/// Read-only department overview. All doctor actions (Call Next, Start,
/// Pause, Skip/Warn, Complete, Refer) now live exclusively in the Patient
/// tab (CurrentPatientScreen) — this avoids two different surfaces being
/// able to act on the same entry with different rules, which specifically
/// mattered for enforcing "no instant skip, warning required" everywhere.
class LiveQueueBody extends ConsumerWidget {
  const LiveQueueBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (profile == null || hospitalId == null) return const Center(child: CircularProgressIndicator());

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder(
      stream: ref.read(_doctorRepoProvider).watchMyDoctorProfile(profile.uid),
      builder: (context, doctorSnap) {
        final doctor = doctorSnap.data;
        if (doctor == null) return const Center(child: CircularProgressIndicator());

        return StreamBuilder<List<QueueEntryModel>>(
          stream: ref.read(queueRepositoryProvider).watchLiveQueue(
            hospitalId: hospitalId,
            date: today,
            departmentId: doctor.departmentId,
          ),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final entries = snap.data!;
            if (entries.isEmpty) return const Center(child: Text('No patients in the queue'));

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final isMine = e.doctorId == profile.uid;
                final color = statusColor(e.status);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text('#${e.tokenNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    title: Text('Token #${e.tokenNumber}'),
                    subtitle: Text('${e.status}${isMine ? ' · assigned to you' : ''} · ${e.priority}'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}