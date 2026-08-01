import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/department_model.dart';
import '../../models/queue_entry_model.dart';
import '../../repositories/walkin_booking_helper.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import 'checkin_screen.dart'; // for queueRepositoryProvider

class PriorityCheckInScreen extends ConsumerStatefulWidget {
  const PriorityCheckInScreen({super.key});

  @override
  ConsumerState<PriorityCheckInScreen> createState() => _PriorityCheckInScreenState();
}

class _PriorityCheckInScreenState extends ConsumerState<PriorityCheckInScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text('Priority Check-In', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'New Emergency Walk-In'),
                Tab(text: 'Escalate Patient'),
              ],
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              dividerColor: AppColors.surfaceVariant,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _NewWalkInEmergencyTab(),
                  _EscalateExistingTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== New Walk-In Emergency Tab ====================

class _NewWalkInEmergencyTab extends ConsumerStatefulWidget {
  const _NewWalkInEmergencyTab();

  @override
  ConsumerState<_NewWalkInEmergencyTab> createState() => _NewWalkInEmergencyTabState();
}

class _NewWalkInEmergencyTabState extends ConsumerState<_NewWalkInEmergencyTab> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _departmentId;
  String _priority = 'critical';
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit(String hospitalId) async {
    if (_nameController.text.trim().isEmpty || _departmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient name and department are required')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final helper = WalkInBookingHelper(
        appointmentRepository: ref.read(appointmentRepositoryProvider),
        queueRepository: ref.read(queueRepositoryProvider),
      );

      final tokenNumber = await helper.bookAndCheckIn(
        displayName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        hospitalId: hospitalId,
        departmentId: _departmentId!,
        priority: _priority,
      );

      if (mounted) {
        _nameController.clear();
        _phoneController.clear();
        setState(() => _departmentId = null);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Priority check-in successful — Token #$tokenNumber'),
            backgroundColor: AppColors.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;

    if (hospitalId == null) {
      return const Center(child: Text('Profile not loaded'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patient Information', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number (optional)', prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: 20),
                  StreamBuilder<List<DepartmentModel>>(
                    stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
                    builder: (context, snap) {
                      final depts = snap.data ?? [];
                      return DropdownButtonFormField<String>(
                        initialValue: _departmentId,
                        decoration: const InputDecoration(labelText: 'Department *', prefixIcon: Icon(Icons.medical_services_outlined)),
                        items: depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                        onChanged: (v) => setState(() => _departmentId = v),
                      );
                    },
                  ),
                  // Triage context — lets the receptionist see how many
                  // emergencies are already waiting in this department
                  // before adding another, since that affects how urgent
                  // this new one really is relative to the others.
                  if (_departmentId != null)
                    StreamBuilder<List<QueueEntryModel>>(
                      stream: ref.read(queueRepositoryProvider).watchLiveQueue(
                        hospitalId: hospitalId,
                        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                        departmentId: _departmentId!,
                      ),
                      builder: (context, snap) {
                        final entries = snap.data ?? [];
                        final existingUrgentCount = entries.where((e) => e.status == 'waiting' && e.priority != 'normal').length;
                        if (existingUrgentCount == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: AppColors.urgent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: AppColors.urgent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$existingUrgentCount other priority patient${existingUrgentCount == 1 ? '' : 's'} already waiting here',
                                    style: TextStyle(color: AppColors.urgent, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Priority Level', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'critical', label: Text('Critical'), icon: Icon(Icons.emergency, size: 18)),
              ButtonSegment(value: 'urgent', label: Text('Urgent'), icon: Icon(Icons.priority_high, size: 18)),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
            style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.emergency_rounded),
            label: Text(_submitting ? 'Processing...' : 'Confirm Priority Check-In'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), backgroundColor: AppColors.critical),
            onPressed: _submitting ? null : () => _submit(hospitalId),
          ),
          const SizedBox(height: 12),
          const Text(
            'This will create an appointment and check the patient in immediately.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ==================== Escalate Existing Patient Tab ====================

class _EscalateExistingTab extends ConsumerWidget {
  const _EscalateExistingTab();

  Future<void> _escalate(
      BuildContext context,
      WidgetRef ref, {
        required String hospitalId,
        required String date,
        required String departmentId,
        required String entryId,
        required String newPriority,
        required String patientName,
      }) async {
    try {
      await ref.read(queueRepositoryProvider).escalatePriority(
        hospitalId: hospitalId,
        date: date,
        departmentId: departmentId,
        entryId: entryId,
        newPriority: newPriority,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$patientName escalated to ${newPriority.toUpperCase()}'), backgroundColor: AppColors.secondary),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to escalate: $e')));
      }
    }
  }

  String _elapsedSince(DateTime? checkedInAt) {
    if (checkedInAt == null) return '';
    final mins = DateTime.now().difference(checkedInAt).inMinutes;
    if (mins < 1) return 'just checked in';
    return 'waiting ${mins}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) {
      return const Center(child: Text('Profile not loaded'));
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<List<DepartmentModel>>(
      stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
      builder: (context, deptSnap) {
        final depts = deptSnap.data ?? [];
        if (depts.isEmpty) {
          return const Center(child: Text('No departments configured'));
        }

        // Flattened into one scrollable list, section-headed by
        // department, instead of a second nested TabBar — swiping within
        // a swipe was awkward, and this also lets a receptionist scan
        // every department's normal-priority queue in one pass without
        // switching tabs repeatedly.
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: depts.map((dept) {
            return StreamBuilder<List<QueueEntryModel>>(
              stream: ref.read(queueRepositoryProvider).watchLiveQueue(hospitalId: hospitalId, date: today, departmentId: dept.id),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${dept.name}: error loading queue', style: const TextStyle(color: AppColors.error)),
                  );
                }
                if (!snap.hasData) return const SizedBox.shrink();

                final waiting = snap.data!.where((e) => e.status == 'waiting' && e.priority == 'normal').toList()
                  ..sort((a, b) => (a.checkedInAt ?? DateTime(0)).compareTo(b.checkedInAt ?? DateTime(0)));

                if (waiting.isEmpty) return const SizedBox.shrink(); // no header shown for empty departments — reduces clutter

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Row(
                        children: [
                          Text(dept.name, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
                            child: Text('${waiting.length} waiting', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    ...waiting.map((e) {
                      final color = priorityColor(e.priority); // 'normal' here, but kept via the shared helper for consistency
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.1),
                            child: Text('#${e.tokenNumber}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                          ),
                          title: Text(e.patientName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_elapsedSince(e.checkedInAt)),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                label: const Text('Urgent'),
                                onPressed: () => _escalate(
                                  context,
                                  ref,
                                  hospitalId: hospitalId,
                                  date: today,
                                  departmentId: dept.id,
                                  entryId: e.id,
                                  newPriority: 'urgent',
                                  patientName: e.patientName,
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.emergency, size: 15),
                                label: const Text('Critical'),
                                style: TextButton.styleFrom(foregroundColor: AppColors.critical),
                                onPressed: () => _escalate(
                                  context,
                                  ref,
                                  hospitalId: hospitalId,
                                  date: today,
                                  departmentId: dept.id,
                                  entryId: e.id,
                                  newPriority: 'critical',
                                  patientName: e.patientName,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}