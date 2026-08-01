import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/hospital_model.dart';
import '../../repositories/hospital_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';

final _hospitalRepoProvider = Provider((ref) => HospitalRepository());

class SkipPolicyScreen extends ConsumerWidget {
  const SkipPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    return Scaffold(
      appBar: AppBar(title: const Text('Skip & Rejoin Policy')),
      body: StreamBuilder<HospitalModel?>(
        stream: ref.read(_hospitalRepoProvider).watchHospital(hospitalId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final hospital = snap.data!;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'When a skipped patient returns and rejoins the queue, where should they be placed?',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                RadioListTile<String>(
                  title: const Text('End of queue'),
                  subtitle: const Text('Rejoin behind everyone currently waiting in their priority tier'),
                  value: 'end_of_queue',
                  groupValue: hospital.skipPolicy,
                  onChanged: (v) => ref.read(_hospitalRepoProvider).updateSkipPolicy(hospitalId: hospitalId, skipPolicy: v!),
                ),
                RadioListTile<String>(
                  title: const Text('After current patient'),
                  subtitle: const Text('Rejoin at the front of their priority tier, seen next after whoever is currently being served'),
                  value: 'after_current',
                  groupValue: hospital.skipPolicy,
                  onChanged: (v) => ref.read(_hospitalRepoProvider).updateSkipPolicy(hospitalId: hospitalId, skipPolicy: v!),
                ),
                const Divider(height: 40),
                const Text(
                  'When a doctor calls a patient who isn\'t present, how long should they be given to report before being skipped?',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                _GraceMinutesPicker(hospitalId: hospitalId, current: hospital.noShowGraceMinutes),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GraceMinutesPicker extends ConsumerWidget {
  const _GraceMinutesPicker({required this.hospitalId, required this.current});
  final String hospitalId;
  final int current;

  static const _options = [2, 5, 10, 15];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      children: _options.map((minutes) {
        return ChoiceChip(
          label: Text('$minutes min'),
          selected: current == minutes,
          onSelected: (_) => ref.read(_hospitalRepoProvider).updateNoShowGraceMinutes(hospitalId: hospitalId, minutes: minutes),
        );
      }).toList(),
    );
  }
}