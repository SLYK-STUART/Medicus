import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../models/department_model.dart';
import '../../models/queue_entry_model.dart';
import '../../repositories/queue_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

final queueRepositoryProvider = Provider((ref) => QueueRepository());

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});
  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Appointments"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Pending'), Tab(text: 'Checked In'), Tab(text: 'Completed')],
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<DepartmentModel>>(
          stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
          builder: (context, deptSnap) {
            final departments = deptSnap.data ?? [];
            final deptNameById = {for (final d in departments) d.id: d.name};

            return StreamBuilder<List<AppointmentModel>>(
              stream: ref.read(appointmentRepositoryProvider).watchTodaysAppointmentsForHospital(hospitalId: hospitalId, date: today),
              builder: (context, apptSnap) {
                if (apptSnap.hasError) return Center(child: Text('Error: ${apptSnap.error}'));
                if (!apptSnap.hasData) return const Center(child: CircularProgressIndicator());

                final all = apptSnap.data!;
                final pending = all.where((a) => a.status == 'booked').toList();
                final checkedIn = all.where((a) => a.status == 'checked_in').toList();
                final completed = all.where((a) => a.status == 'completed').toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(child: _StatChip(label: 'Total', value: all.length, color: AppColors.textSecondary)),
                          const SizedBox(width: 8),
                          Expanded(child: _StatChip(label: 'Waiting', value: pending.length, color: AppColors.primary)),
                          const SizedBox(width: 8),
                          Expanded(child: _StatChip(label: 'Checked In', value: checkedIn.length, color: AppColors.secondary)),
                          const SizedBox(width: 8),
                          Expanded(child: _StatChip(label: 'Done', value: completed.length, color: const Color(0xFF15803D))),
                        ],
                      ),
                    ),
                    _NowServingRow(hospitalId: hospitalId, date: today, departments: departments),
                    const Divider(height: 1),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _PendingList(appointments: pending, deptNameById: deptNameById),
                          _CheckedInList(appointments: checkedIn, deptNameById: deptNameById),
                          _CompletedList(appointments: completed, deptNameById: deptNameById),
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
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Shows who's actively being served (called/in_consultation) per
/// department. One nested StreamBuilder per department — no collection-
/// group query is set up in this project, and adding one would be more
/// infra than this widget needs at the department counts involved here.
class _NowServingRow extends ConsumerWidget {
  const _NowServingRow({required this.hospitalId, required this.date, required this.departments});
  final String hospitalId;
  final String date;
  final List<DepartmentModel> departments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (departments.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: departments.map((dept) {
          return StreamBuilder<List<QueueEntryModel>>(
            stream: ref.read(queueRepositoryProvider).watchLiveQueue(hospitalId: hospitalId, date: date, departmentId: dept.id),
            builder: (context, snap) {
              final active = (snap.data ?? []).where((e) => e.status == 'called' || e.status == 'in_consultation').toList();
              return Container(
                width: 160,
                margin: const EdgeInsets.only(right: 10, bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dept.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    Text(
                      active.isEmpty ? 'No one being seen' : 'Now serving #${active.first.tokenNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        color: active.isEmpty ? AppColors.textSecondary : AppColors.primary,
                        fontWeight: active.isEmpty ? FontWeight.normal : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList({required this.appointments, required this.deptNameById});
  final List<AppointmentModel> appointments;
  final Map<String, String> deptNameById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appointments.isEmpty) return const Center(child: Text('No pending appointments today'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: appointments.length,
      itemBuilder: (context, i) {
        final a = appointments[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.surfaceVariant,
              child: Text('#${a.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            title: Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${deptNameById[a.departmentId] ?? a.departmentId}${a.scheduledTimeSlot != null ? ' · ${a.scheduledTimeSlot}' : ''}'),
            trailing: FilledButton(
              onPressed: () async {
                try {
                  await ref.read(queueRepositoryProvider).checkIn(
                    appointmentId: a.id,
                    patientId: a.patientId,
                    patientName: a.patientName,
                    patientPhoneNumber: a.patientPhoneNumber,
                    doctorId: a.doctorId,
                    tokenNumber: a.tokenNumber,
                    hospitalId: a.hospitalId,
                    date: a.scheduledDate,
                    departmentId: a.departmentId,
                  );
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked in')));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
              child: const Text('Check In'),
            ),
          ),
        );
      },
    );
  }
}

class _CheckedInList extends StatelessWidget {
  const _CheckedInList({required this.appointments, required this.deptNameById});
  final List<AppointmentModel> appointments;
  final Map<String, String> deptNameById;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) return const Center(child: Text('No one checked in yet today'));
    final sorted = [...appointments]..sort((a, b) => (a.checkedInAt ?? DateTime(0)).compareTo(b.checkedInAt ?? DateTime(0)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final a = sorted[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
              child: Text('#${a.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.secondary)),
            ),
            title: Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(deptNameById[a.departmentId] ?? a.departmentId),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.check_circle, color: AppColors.secondary, size: 18),
                if (a.checkedInAt != null)
                  Text(DateFormat('h:mm a').format(a.checkedInAt!), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompletedList extends StatelessWidget {
  const _CompletedList({required this.appointments, required this.deptNameById});
  final List<AppointmentModel> appointments;
  final Map<String, String> deptNameById;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) return const Center(child: Text('No completed consultations yet today'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: appointments.length,
      itemBuilder: (context, i) {
        final a = appointments[i];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0x1A15803D), child: Icon(Icons.check, color: Color(0xFF15803D))),
            title: Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${deptNameById[a.departmentId] ?? a.departmentId} · #${a.tokenNumber}'),
          ),
        );
      },
    );
  }
}