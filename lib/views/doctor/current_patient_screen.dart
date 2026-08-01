import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/department_model.dart';
import '../../models/doctor_model.dart';
import '../../models/queue_entry_model.dart';
import '../../repositories/referral_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import '../receptionist/checkin_screen.dart'; // queueRepositoryProvider

final _referralRepoProvider = Provider((ref) => ReferralRepository());

/// A single resumable paused-patient row. Used both when there's no
/// active patient (paused list shown full-page) and when there IS an
/// active patient (paused list shown as a section above it) — every
/// paused patient always gets its own Resume action, regardless of how
/// many are paused at once.
class _PausedPatientTile extends ConsumerWidget {
  const _PausedPatientTile({
    required this.entry,
    required this.hospitalId,
    required this.departmentId,
    required this.date,
  });

  final QueueEntryModel entry;
  final String hospitalId;
  final String departmentId;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: Colors.amber.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white,
          child: Text('#${entry.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        title: Text('Token #${entry.tokenNumber}'),
        subtitle: const Text('Paused mid-consultation'),
        trailing: FilledButton(
          onPressed: () => ref.read(queueRepositoryProvider).resumeConsultation(
            hospitalId: hospitalId,
            date: date,
            departmentId: departmentId,
            entryId: entry.id,
          ),
          child: const Text('Resume'),
        ),
      ),
    );
  }
}

class CurrentPatientScreen extends ConsumerStatefulWidget {
  const CurrentPatientScreen({super.key, required this.hospitalId, required this.doctor});
  final String hospitalId;
  final DoctorModel doctor;

  @override
  ConsumerState<CurrentPatientScreen> createState() => _CurrentPatientScreenState();
}

class _CurrentPatientScreenState extends ConsumerState<CurrentPatientScreen> {
  bool _callingNext = false;
  bool _autoSkipTriggered = false; // guards against firing markSkipped more than once per countdown

  /// Extra bottom padding so scrollable content can clear the floating
  /// nav bar in DoctorDashboardScreen (Scaffold.extendBody draws content
  /// underneath it). Mirrors that bar's height (64) + its own bottom
  /// margin (12) + the device's safe-area inset, plus a little breathing
  /// room so the last item isn't flush against the bar.
  double _bottomClearance(BuildContext context) {
    return 64 + 12 + MediaQuery.of(context).padding.bottom + 16;
  }

  Future<void> _handleCallNext() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() => _callingNext = true);
    try {
      final result = await ref.read(queueRepositoryProvider).callNextPatient(
        hospitalId: widget.hospitalId,
        date: today,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Now calling token #${result.tokenNumber}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _callingNext = false);
    }
  }

  Future<void> _handleComplete(QueueEntryModel entry, String today) async {
    try {
      await ref.read(queueRepositoryProvider).updateStatus(
        hospitalId: widget.hospitalId,
        date: today,
        departmentId: widget.doctor.departmentId,
        entryId: entry.id,
        status: 'completed',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not end session: $e')));
      }
      return;
    }
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Consultation Complete'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'refer'), child: const Text('Refer to Another Department')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'followup'), child: const Text('Schedule Follow-up')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, null), child: const Text('Done, No Further Action')),
        ],
      ),
    );

    if (action == 'refer') {
      await _showReferralDialog(entry);
    } else if (action == 'followup') {
      await _showFollowUpDialog(entry.appointmentId);
    }
  }

  Future<void> _showReferralDialog(QueueEntryModel entry) async {
    final departments = await ref.read(bookingDepartmentRepoProvider).watchDepartments(widget.hospitalId).first;
    final options = departments.where((d) => d.id != widget.doctor.departmentId).toList();
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other departments to refer to')));
      return;
    }
    final selected = await showDialog<DepartmentModel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Refer to Department'),
        children: options.map((d) => SimpleDialogOption(onPressed: () => Navigator.pop(context, d), child: Text(d.name))).toList(),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      final result = await ref.read(_referralRepoProvider).createReferral(
        originAppointmentId: entry.appointmentId,
        targetDepartmentId: selected.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Referred to ${selected.name} — token #${result.tokenNumber}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Referral failed: $e')));
    }
  }

  Future<void> _showFollowUpDialog(String appointmentId) async {
    final daysController = TextEditingController(text: '14');
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schedule Follow-up'),
        content: TextField(
          controller: daysController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days from today'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(daysController.text)), child: const Text('Schedule')),
        ],
      ),
    );
    if (days == null || days < 1 || !mounted) return;
    try {
      final result = await ref.read(_referralRepoProvider).createFollowUp(originAppointmentId: appointmentId, daysFromNow: days);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Follow-up scheduled for ${result.scheduledDate} — token #${result.tokenNumber}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scheduling failed: $e')));
    }
  }

  Future<void> _handleWarn(QueueEntryModel entry, String today) async {
    try {
      await ref.read(queueRepositoryProvider).warnPatientDelay(
        hospitalId: widget.hospitalId,
        date: today,
        departmentId: widget.doctor.departmentId,
        entryId: entry.id,
      );
      _autoSkipTriggered = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient notified of grace period')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _checkAutoSkip(QueueEntryModel entry, String today) {
    if (_autoSkipTriggered) return;
    if (entry.status != 'called' || entry.graceDeadline == null) return;
    if (DateTime.now().isBefore(entry.graceDeadline!)) return;

    _autoSkipTriggered = true;
    ref.read(queueRepositoryProvider).markSkipped(
      hospitalId: widget.hospitalId,
      date: today,
      departmentId: widget.doctor.departmentId,
      entryId: entry.id,
    );
  }

  Widget _buildCallNextButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: const Icon(Icons.campaign),
        label: Text(_callingNext ? 'Calling...' : "I'm Ready — Call Next Patient"),
        onPressed: _callingNext ? null : _handleCallNext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final myUid = ref.watch(currentUserProfileProvider).value?.uid;

    if (myUid == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Paused entries never appear in watchLiveQueue — that query's
    // whereIn deliberately excludes 'paused' (it's scoped to actual
    // waiting-room statuses for other screens like the receptionist
    // view). So paused patients need their own stream here, or a
    // doctor's paused patient silently vanishes from this page the
    // moment they pause a consultation.
    return StreamBuilder<List<QueueEntryModel>>(
      stream: ref.read(queueRepositoryProvider).watchPausedEntriesForDoctor(
        hospitalId: widget.hospitalId,
        date: today,
        departmentId: widget.doctor.departmentId,
        doctorId: myUid,
      ),
      builder: (context, pausedSnap) {
        final paused = pausedSnap.data ?? [];
        return _buildLiveQueueSection(context, today, myUid, paused);
      },
    );
  }

  Widget _buildLiveQueueSection(BuildContext context, String today, String myUid, List<QueueEntryModel> paused) {
    return StreamBuilder<List<QueueEntryModel>>(
      stream: ref.read(queueRepositoryProvider).watchLiveQueue(
        hospitalId: widget.hospitalId,
        date: today,
        departmentId: widget.doctor.departmentId,
      ),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final entries = snap.data!;
        // Scoped to THIS doctor only — previously this compared status
        // alone across the whole department, so in a multi-doctor
        // department one doctor's screen could show another doctor's
        // in-consultation patient as "active." Fixed here.
        final active = entries.where((e) => e.doctorId == myUid && (e.status == 'called' || e.status == 'in_consultation')).toList();
        final activeEntry = active.isEmpty ? null : active.first;
        final waitingCount = entries.where((e) => e.status == 'waiting').length;
        final nextWaiting = entries.where((e) => e.status == 'waiting').toList();

        if (activeEntry == null) {
          if (paused.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, _bottomClearance(context)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('No active patient', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    _buildCallNextButton(),
                  ],
                ),
              ),
            );
          }

          // Nothing active, but at least one paused patient exists —
          // show resume prompts, plus Call Next above them: preserved from
          // the original queue-tab logic, a doctor could call a new
          // patient while one of theirs sat paused (paused was never
          // counted in hasActivePatient there) — carried over unchanged.
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, _bottomClearance(context)),
            children: [
              _buildCallNextButton(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_outline, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Text('Paused', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              ...paused.map((e) => _PausedPatientTile(
                entry: e,
                hospitalId: widget.hospitalId,
                departmentId: widget.doctor.departmentId,
                date: today,
              )),
            ],
          );
        }

        final pColor = priorityColor(activeEntry.priority);

        return StreamBuilder<List<DepartmentModel>>(
          stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(widget.hospitalId),
          builder: (context, deptSnap) {
            final deptName = (deptSnap.data ?? [])
                .firstWhere(
                  (d) => d.id == widget.doctor.departmentId,
              orElse: () => DepartmentModel(id: '', hospitalId: '', name: widget.doctor.departmentId),
            )
                .name;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, _bottomClearance(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (paused.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.pause_circle_outline, color: Colors.amber.shade800, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${paused.length} paused',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    ...paused.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PausedPatientTile(
                        entry: e,
                        hospitalId: widget.hospitalId,
                        departmentId: widget.doctor.departmentId,
                        date: today,
                      ),
                    )),
                    const SizedBox(height: 4),
                  ],

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                          child: Text('#${activeEntry.tokenNumber}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        if (activeEntry.priority != 'normal')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: pColor, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              activeEntry.priority.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                        const Spacer(),
                        if (activeEntry.checkedInAt != null)
                          Text('Check-in ${DateFormat('h:mm a').format(activeEntry.checkedInAt!)}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.surfaceVariant,
                            child: Icon(Icons.person, color: AppColors.primary, size: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Token #${activeEntry.tokenNumber}',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Patient identity is hidden for privacy',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(child: _InfoTile(icon: Icons.category_outlined, label: 'Department', value: deptName)),
                      const SizedBox(width: 10),
                      Expanded(child: _InfoTile(icon: Icons.meeting_room_outlined, label: 'Room', value: widget.doctor.roomNumber ?? 'Not set')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _InfoTile(icon: Icons.medical_services_outlined, label: 'Doctor', value: widget.doctor.displayName)),
                      const SizedBox(width: 10),
                      Expanded(child: _InfoTile(icon: Icons.timer_outlined, label: 'Avg. Duration', value: '~${widget.doctor.avgConsultationMinutes} min')),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (activeEntry.status == 'in_consultation' && activeEntry.consultationStartedAt != null)
                    _SessionTimer(startedAt: activeEntry.consultationStartedAt!),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_outlined, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('$waitingCount patient${waitingCount == 1 ? '' : 's'} waiting after this')),
                        if (nextWaiting.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: Text('Next: #${nextWaiting.first.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (activeEntry.status == 'called')
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Consultation'),
                      onPressed: () => ref.read(queueRepositoryProvider).updateStatus(
                        hospitalId: widget.hospitalId,
                        date: today,
                        departmentId: widget.doctor.departmentId,
                        entryId: activeEntry.id,
                        status: 'in_consultation',
                      ),
                    ),
                  if (activeEntry.status == 'in_consultation')
                    FilledButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Complete Consultation'),
                      onPressed: () => _handleComplete(activeEntry, today),
                    ),
                  const SizedBox(height: 10),

                  if (activeEntry.status == 'called' && activeEntry.warnedAt != null && activeEntry.graceDeadline != null)
                    _GraceCountdown(
                      deadline: activeEntry.graceDeadline!,
                      onExpired: () => _checkAutoSkip(activeEntry, today),
                    ),
                  if (activeEntry.status == 'called' && activeEntry.warnedAt != null) const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text('Call Next'),
                          onPressed: null, // disabled here — an active patient already exists whenever this branch renders
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (activeEntry.status == 'in_consultation')
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.pause_circle_outline),
                            label: const Text('Pause Session'),
                            onPressed: () => ref.read(queueRepositoryProvider).pauseConsultation(
                              hospitalId: widget.hospitalId,
                              date: today,
                              departmentId: widget.doctor.departmentId,
                              entryId: activeEntry.id,
                            ),
                          ),
                        ),
                      if (activeEntry.status == 'called' && activeEntry.warnedAt == null)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.hourglass_top_outlined),
                            label: const Text('Warn — Start Grace Period'),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.urgent, side: const BorderSide(color: AppColors.urgent)),
                            onPressed: () => _handleWarn(activeEntry, today),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (activeEntry.status == 'in_consultation')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.call_split),
                      label: const Text('Refer to Another Department'),
                      onPressed: () => _showReferralDialog(activeEntry),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }
}

class _SessionTimer extends StatefulWidget {
  const _SessionTimer({required this.startedAt});
  final DateTime startedAt;

  @override
  State<_SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<_SessionTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          const Text('Session Duration', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$minutes:$seconds', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(width: 4),
          const Text('min', style: TextStyle(color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _GraceCountdown extends StatefulWidget {
  const _GraceCountdown({required this.deadline, required this.onExpired});
  final DateTime deadline;
  final VoidCallback onExpired;

  @override
  State<_GraceCountdown> createState() => _GraceCountdownState();
}

class _GraceCountdownState extends State<_GraceCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().isAfter(widget.deadline)) widget.onExpired();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline.difference(DateTime.now());
    final expired = remaining.isNegative;
    final minutes = expired ? 0 : remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = expired ? 0 : remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.urgent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.hourglass_bottom, color: AppColors.urgent),
          const SizedBox(width: 10),
          const Text('Grace period', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            expired ? 'Expired — skipping...' : '$minutes:$seconds',
            style: TextStyle(color: AppColors.urgent, fontWeight: FontWeight.w800, fontSize: expired ? 14 : 22),
          ),
        ],
      ),
    );
  }
}