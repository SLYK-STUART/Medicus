import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../models/department_model.dart';
import '../../models/doctor_model.dart';
import '../../models/queue_entry_model.dart';
import '../../repositories/doctor_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import '../receptionist/checkin_screen.dart'; // queueRepositoryProvider

final _doctorRepoProvider = Provider((ref) => DoctorRepository());

const _highLoadThreshold = 8;

class HospitalAdminHomeScreen extends ConsumerStatefulWidget {
  const HospitalAdminHomeScreen({super.key});
  @override
  ConsumerState<HospitalAdminHomeScreen> createState() => _HospitalAdminHomeScreenState();
}

class _HospitalAdminHomeScreenState extends ConsumerState<HospitalAdminHomeScreen> {
  final _searchController = TextEditingController();
  String? _appointmentFilterDeptId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<DepartmentModel>>(
          stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
          builder: (context, deptSnap) {
            final departments = deptSnap.data ?? [];

            return StreamBuilder<List<DoctorModel>>(
              stream: ref.read(_doctorRepoProvider).watchAllDoctorsForHospital(hospitalId),
              builder: (context, doctorSnap) {
                final doctors = doctorSnap.data ?? [];
                final doctorsByDept = <String, List<DoctorModel>>{};
                for (final d in doctors) {
                  doctorsByDept.putIfAbsent(d.departmentId, () => []).add(d);
                }
                final doctorNameById = {for (final d in doctors) d.uid: d.displayName};

                return StreamBuilder<List<AppointmentModel>>(
                  stream: ref.read(appointmentRepositoryProvider).watchTodaysAppointmentsForHospital(hospitalId: hospitalId, date: today),
                  builder: (context, apptSnap) {
                    if (apptSnap.hasError) return Center(child: Text('Error: ${apptSnap.error}'));
                    final appointments = apptSnap.data ?? [];

                    // Everything below is derived purely from appointments —
                    // no queue_entries involvement at this level at all.
                    final completedByDept = <String, int>{};
                    final bookedByDept = <String, int>{};
                    for (final a in appointments) {
                      if (a.status == 'completed') completedByDept[a.departmentId] = (completedByDept[a.departmentId] ?? 0) + 1;
                      if (a.status == 'booked') bookedByDept[a.departmentId] = (bookedByDept[a.departmentId] ?? 0) + 1;
                    }
                    final completedToday = appointments.where((a) => a.status == 'completed').length;
                    final activeDeptCount = departments.where((d) => (doctorsByDept[d.id]?.isNotEmpty ?? false)).length;
                    final avgConsultOverall = doctors.isEmpty
                        ? null
                        : (doctors.map((d) => d.avgConsultationMinutes).reduce((a, b) => a + b) / doctors.length).round();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _Header(
                          searchController: _searchController,
                          onSearchChanged: () => setState(() {}),
                          onAddStaff: () => context.push('/admin/staff/create'),
                          onSignOut: () => ref.read(authFormControllerProvider.notifier).signOut(),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 100,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _StatCard(title: "Today's Patients", value: '${appointments.length}', highlighted: true),
                              _StatCard(title: 'Active Departments', value: '$activeDeptCount / ${departments.length}'),
                              _StatCard(title: 'Avg Consult Time', value: avgConsultOverall == null ? '—' : '${avgConsultOverall}m'),
                              _StatCard(title: 'Completed Today', value: '$completedToday'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _SectionHeader(title: 'Department Status', actionLabel: 'Manage', onAction: () => context.push('/admin/departments')),
                        const SizedBox(height: 10),
                        if (departments.isEmpty)
                          const _EmptyHint(text: 'No departments set up yet')
                        else
                        // Each card owns and self-manages its own live
                        // queue stream. It never reports data upward — no
                        // parent setState is triggered by anything inside
                        // this list, which is what keeps this section
                        // stable no matter how often queue_entries writes.
                          ...departments.map((dept) => _DepartmentStatusCard(
                            department: dept,
                            doctorCount: doctorsByDept[dept.id]?.length ?? 0,
                            completedToday: completedByDept[dept.id] ?? 0,
                            bookedToday: bookedByDept[dept.id] ?? 0,
                          )),
                        const SizedBox(height: 24),
                        _SectionHeader(title: 'Staff', actionLabel: 'View All', onAction: () => context.push('/admin/doctors')),
                        const SizedBox(height: 10),
                        if (doctors.isEmpty)
                          const _EmptyHint(text: 'No doctors added yet')
                        else
                          ...doctors.map((d) => _StaffRow(doctor: d, hospitalId: hospitalId)),
                        const SizedBox(height: 24),
                        _SectionHeader(title: "Today's Appointments", actionLabel: null, onAction: null),
                        const SizedBox(height: 10),
                        _AppointmentsFilterBar(
                          departments: departments,
                          selectedDeptId: _appointmentFilterDeptId,
                          onDeptChanged: (v) => setState(() => _appointmentFilterDeptId = v),
                        ),
                        const SizedBox(height: 10),
                        _TodaysAppointmentsList(
                          appointments: appointments,
                          searchQuery: _searchController.text,
                          filterDeptId: _appointmentFilterDeptId,
                          departments: departments,
                          doctorNameById: doctorNameById,
                        ),
                      ],
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

class _Header extends StatelessWidget {
  const _Header({required this.searchController, required this.onSearchChanged, required this.onAddStaff, required this.onSignOut});
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final VoidCallback onAddStaff;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
                  Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()), style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.logout), onPressed: onSignOut),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(hintText: 'Search patients by name or token', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (_) => onSearchChanged(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onAddStaff,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Add Staff'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
            ),
          ],
        ),
      ],
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
      width: 150,
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
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: highlighted ? Colors.white : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actionLabel, required this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(text, style: Theme.of(context).textTheme.bodyMedium));
}

/// Fully self-contained. Owns its own watchLiveQueue stream, computes and
/// displays its own waiting/in-progress counts and its own alert badge —
/// nothing here is ever reported to a parent widget.
class _DepartmentStatusCard extends ConsumerWidget {
  const _DepartmentStatusCard({
    required this.department,
    required this.doctorCount,
    required this.completedToday,
    required this.bookedToday,
  });
  final DepartmentModel department;
  final int doctorCount;
  final int completedToday;
  final int bookedToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<List<QueueEntryModel>>(
      stream: ref.read(queueRepositoryProvider).watchLiveQueue(hospitalId: department.hospitalId, date: today, departmentId: department.id),
      builder: (context, snap) {
        final entries = snap.data ?? [];
        final waiting = entries.where((e) => e.status == 'waiting').length;
        final inProgress = entries.where((e) => e.status == 'called' || e.status == 'in_consultation').length;
        final active = doctorCount > 0;
        final highLoad = waiting > _highLoadThreshold;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: (!active || highLoad) ? BorderSide(color: (!active ? AppColors.urgent : AppColors.error).withValues(alpha: 0.4)) : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(department.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('$doctorCount doctor${doctorCount == 1 ? '' : 's'} assigned', style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (active ? const Color(0xFF15803D) : AppColors.textSecondary).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        active ? 'Active' : 'Inactive',
                        style: TextStyle(color: active ? const Color(0xFF15803D) : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniStat(label: 'Booked', value: '$bookedToday'),
                    _MiniStat(label: 'Waiting', value: '$waiting'),
                    _MiniStat(label: 'In Prog.', value: '$inProgress'),
                    _MiniStat(label: 'Done', value: '$completedToday'),
                  ],
                ),
                if (!active)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: _InlineAlert(text: 'No doctor assigned', color: AppColors.urgent),
                  )
                else if (highLoad)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: _InlineAlert(text: 'High load — consider reassigning staff', color: AppColors.error),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineAlert extends StatelessWidget {
  const _InlineAlert({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: color, size: 16),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

/// Self-contained: queries only this one doctor's own department queue,
/// checks locally whether THIS doctor has an active entry. No shared
/// state with other _StaffRow instances, even ones in the same department.
class _StaffRow extends ConsumerWidget {
  const _StaffRow({required this.doctor, required this.hospitalId});
  final DoctorModel doctor;
  final String hospitalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<List<QueueEntryModel>>(
      stream: ref.read(queueRepositoryProvider).watchLiveQueue(hospitalId: hospitalId, date: today, departmentId: doctor.departmentId),
      builder: (context, snap) {
        final entries = snap.data ?? [];
        final isActive = entries.any((e) => e.doctorId == doctor.uid && (e.status == 'called' || e.status == 'in_consultation'));

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: AppColors.surfaceVariant, child: Icon(Icons.person, color: AppColors.primary)),
            title: Text(doctor.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${doctor.departmentId}${doctor.roomNumber != null ? ' · Room ${doctor.roomNumber}' : ''}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: isActive ? const Color(0xFF15803D) : AppColors.surfaceVariant, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(isActive ? 'With patient' : 'Free', style: TextStyle(fontSize: 11, color: isActive ? const Color(0xFF15803D) : AppColors.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppointmentsFilterBar extends StatelessWidget {
  const _AppointmentsFilterBar({required this.departments, required this.selectedDeptId, required this.onDeptChanged});
  final List<DepartmentModel> departments;
  final String? selectedDeptId;
  final ValueChanged<String?> onDeptChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(label: const Text('All Departments'), selected: selectedDeptId == null, onSelected: (_) => onDeptChanged(null)),
          const SizedBox(width: 8),
          ...departments.map((d) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(d.name), selected: selectedDeptId == d.id, onSelected: (_) => onDeptChanged(d.id)),
          )),
        ],
      ),
    );
  }
}

class _TodaysAppointmentsList extends StatelessWidget {
  const _TodaysAppointmentsList({
    required this.appointments,
    required this.searchQuery,
    required this.filterDeptId,
    required this.departments,
    required this.doctorNameById,
  });
  final List<AppointmentModel> appointments;
  final String searchQuery;
  final String? filterDeptId;
  final List<DepartmentModel> departments;
  final Map<String, String> doctorNameById;

  @override
  Widget build(BuildContext context) {
    final deptNameById = {for (final d in departments) d.id: d.name};
    final query = searchQuery.trim().toLowerCase();

    var filtered = appointments;
    if (filterDeptId != null) filtered = filtered.where((a) => a.departmentId == filterDeptId).toList();
    if (query.isNotEmpty) {
      filtered = filtered.where((a) => a.patientName.toLowerCase().contains(query) || a.tokenNumber.toString().startsWith(query)).toList();
    }
    filtered = [...filtered]..sort((a, b) => b.tokenNumber.compareTo(a.tokenNumber));

    if (filtered.isEmpty) return const _EmptyHint(text: 'No matching appointments today');

    final shown = filtered.take(15).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...shown.map((a) {
          final color = statusColor(a.status);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Text('#${a.tokenNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12))),
              title: Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${a.doctorId != null ? (doctorNameById[a.doctorId] ?? 'Unknown doctor') : 'Unassigned'} · ${deptNameById[a.departmentId] ?? a.departmentId}'),
              trailing: Text(a.status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          );
        }),
        if (filtered.length > 15)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('Showing 15 of ${filtered.length}', style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}