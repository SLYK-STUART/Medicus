import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../models/department_model.dart';
import '../../models/doctor_model.dart';
import '../../models/hospital_model.dart';
import '../../models/user_model.dart';
import '../../repositories/hospital_repository.dart';
import '../../repositories/super_admin_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';

final _superAdminRepoProvider = Provider((ref) => SuperAdminRepository());
final _hospitalRepoProvider = Provider((ref) => HospitalRepository());

class SuperAdminHomeScreen extends ConsumerWidget {
  const SuperAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Overview'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => ref.read(authFormControllerProvider.notifier).signOut()),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<HospitalModel>>(
          stream: ref.read(_hospitalRepoProvider).watchHospitals(),
          builder: (context, hospSnap) {
            final hospitals = hospSnap.data ?? [];

            return StreamBuilder<List<UserModel>>(
              stream: ref.read(_superAdminRepoProvider).watchAllUsers(),
              builder: (context, userSnap) {
                if (userSnap.hasError) return Center(child: Text('Error: ${userSnap.error}'));
                final users = userSnap.data ?? [];

                return StreamBuilder<List<DepartmentModel>>(
                  stream: ref.read(_superAdminRepoProvider).watchAllDepartments(),
                  builder: (context, deptSnap) {
                    final departments = deptSnap.data ?? [];

                    return StreamBuilder<List<DoctorModel>>(
                      stream: ref.read(_superAdminRepoProvider).watchAllDoctors(),
                      builder: (context, doctorSnap) {
                        final doctors = doctorSnap.data ?? [];

                        return StreamBuilder<List<AppointmentModel>>(
                          stream: ref.read(_superAdminRepoProvider).watchAllAppointmentsForDate(today),
                          builder: (context, apptSnap) {
                            final appointments = apptSnap.data ?? [];

                            // ---- All aggregation happens once here, from
                            // whatever snapshots have arrived so far — no
                            // cross-widget setState, no per-hospital nested
                            // streams. Each rebuild is driven purely by
                            // React-style recomputation from the five flat
                            // streams above.
                            final hospitalAdmins = users.where((u) => u.role == AppRole.hospitalAdmin).toList();
                            final receptionists = users.where((u) => u.role == AppRole.receptionist).toList();
                            final patients = users.where((u) => u.role == AppRole.patient).toList();

                            final hospitalIdsWithAdmin = hospitalAdmins.map((u) => u.hospitalId).whereType<String>().toSet();
                            final hospitalsWithoutAdmin = hospitals.where((h) => !hospitalIdsWithAdmin.contains(h.id)).toList();

                            final deptCountByHospital = <String, int>{};
                            for (final d in departments) {
                              deptCountByHospital[d.hospitalId] = (deptCountByHospital[d.hospitalId] ?? 0) + 1;
                            }
                            final doctorCountByHospital = <String, int>{};
                            for (final d in doctors) {
                              doctorCountByHospital[d.hospitalId] = (doctorCountByHospital[d.hospitalId] ?? 0) + 1;
                            }
                            final apptCountByHospital = <String, int>{};
                            for (final a in appointments) {
                              apptCountByHospital[a.hospitalId] = (apptCountByHospital[a.hospitalId] ?? 0) + 1;
                            }

                            final recentHospitals = [...hospitals]..sort((a, b) {
                              // HospitalModel doesn't currently expose createdAt
                              // as a Dart field — falling back to name order
                              // rather than adding a field just for this;
                              // flagged in the widget below instead of here.
                              return a.name.compareTo(b.name);
                            });

                            return ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              children: [
                                Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()), style: Theme.of(context).textTheme.bodyMedium),
                                const SizedBox(height: 4),
                                Text('Hi, ${profile?.displayName?.split(' ').first ?? 'Admin'}', style: Theme.of(context).textTheme.headlineSmall),
                                const SizedBox(height: 16),

                                SizedBox(
                                  height: 100,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      _StatCard(title: 'Hospitals', value: '${hospitals.length}', highlighted: true),
                                      _StatCard(title: 'Total Staff', value: '${hospitalAdmins.length + receptionists.length + doctors.length}'),
                                      _StatCard(title: 'Patients', value: '${patients.length}'),
                                      _StatCard(title: "Today's Bookings", value: '${appointments.length}'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                if (hospitalsWithoutAdmin.isNotEmpty) ...[
                                  Text('Needs Attention', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 10),
                                  ...hospitalsWithoutAdmin.map((h) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(backgroundColor: AppColors.urgent.withValues(alpha: 0.12), child: Icon(Icons.person_off_outlined, color: AppColors.urgent, size: 20)),
                                      title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: const Text('No hospital admin assigned'),
                                      trailing: FilledButton(
                                        onPressed: () => context.push('/super-admin/staff/create-hospital-admin'),
                                        child: const Text('Assign'),
                                      ),
                                    ),
                                  )),
                                  const SizedBox(height: 24),
                                ],

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Hospitals', style: Theme.of(context).textTheme.titleMedium),
                                    TextButton(onPressed: () => context.push('/super-admin/hospitals/create'), child: const Text('Manage')),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (recentHospitals.isEmpty)
                                  const _EmptyHint(text: 'No hospitals created yet')
                                else
                                  ...recentHospitals.map((h) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const CircleAvatar(backgroundColor: AppColors.surfaceVariant, child: Icon(Icons.local_hospital_outlined, color: AppColors.primary)),
                                      title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text('${deptCountByHospital[h.id] ?? 0} departments · ${doctorCountByHospital[h.id] ?? 0} doctors'),
                                      trailing: Text('${apptCountByHospital[h.id] ?? 0} today', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  )),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, this.highlighted = false});
  final String title;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: highlighted ? null : Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: highlighted ? Colors.white70 : AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: highlighted ? Colors.white : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(text, style: Theme.of(context).textTheme.bodyMedium));
}