import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/department_model.dart';
import '../../models/hospital_model.dart';
import '../../models/queue_entry_model.dart';
import '../../repositories/hospital_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import 'checkin_screen.dart'; // queueRepositoryProvider

final _hospitalRepoProvider = Provider((ref) => HospitalRepository());

class SkippedPatientsScreen extends ConsumerWidget {
  const SkippedPatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Skipped Patients')),
      body: StreamBuilder<HospitalModel?>(
        stream: ref.read(_hospitalRepoProvider).watchHospital(hospitalId),
        builder: (context, hospSnap) {
          final hospital = hospSnap.data;
          if (hospital == null) return const Center(child: CircularProgressIndicator());

          return StreamBuilder<List<DepartmentModel>>(
            stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
            builder: (context, deptSnap) {
              final depts = deptSnap.data ?? [];
              if (depts.isEmpty) return const Center(child: Text('No departments yet'));

              return ListView(
                children: depts.map((dept) {
                  return StreamBuilder<List<QueueEntryModel>>(
                    stream: ref.read(queueRepositoryProvider).watchSkippedEntries(
                      hospitalId: hospitalId,
                      date: today,
                      departmentId: dept.id,
                    ),
                    builder: (context, snap) {
                      final skipped = snap.data ?? [];
                      if (skipped.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(dept.name, style: Theme.of(context).textTheme.titleMedium),
                          ),
                          ...skipped.map((e) => ListTile(
                            leading: CircleAvatar(child: Text('#${e.tokenNumber}')),
                            title: Text('Patient: ${e.patientName}'),
                            subtitle: Text('Priority: ${e.priority}'),
                            trailing: FilledButton(
                              onPressed: () async {
                                try {
                                  await ref.read(queueRepositoryProvider).rejoinPatient(
                                    hospitalId: hospitalId,
                                    date: today,
                                    departmentId: dept.id,
                                    entryId: e.id,
                                    skipPolicy: hospital.skipPolicy,
                                    priority: e.priority,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejoined queue')));
                                  }
                                } catch (err) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $err')));
                                  }
                                }
                              },
                              child: const Text('Rejoin'),
                            ),
                          )),
                        ],
                      );
                    },
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}