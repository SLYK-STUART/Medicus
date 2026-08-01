import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/department_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';

final departmentRepositoryProvider = Provider((ref) => DepartmentRepository());

class DepartmentCreateScreen extends ConsumerStatefulWidget {
  const DepartmentCreateScreen({super.key});
  @override
  ConsumerState<DepartmentCreateScreen> createState() => _DepartmentCreateScreenState();
}

class _DepartmentCreateScreenState extends ConsumerState<DepartmentCreateScreen> {
  final _nameController = TextEditingController();
  final _openController = TextEditingController(text: '08:00');
  final _closeController = TextEditingController(text: '17:00');
  final _durationController = TextEditingController(text: '30');
  final _capacityController = TextEditingController(text: '5');
  bool _loading = false;

  Future<void> _submit(String hospitalId) async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(departmentRepositoryProvider).createDepartment(
        hospitalId: hospitalId,
        name: _nameController.text.trim(),
        openTime: _openController.text.trim().isEmpty ? '08:00' : _openController.text.trim(),
        closeTime: _closeController.text.trim().isEmpty ? '17:00' : _closeController.text.trim(),
        slotDurationMinutes: int.tryParse(_durationController.text) ?? 30,
        slotCapacity: int.tryParse(_capacityController.text) ?? 5,
      );
      _nameController.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Department added')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    final departmentsAsync = ref.watch(departmentRepositoryProvider).watchDepartments(hospitalId);

    return Scaffold(
      appBar: AppBar(title: const Text('Departments')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Department name')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _openController, decoration: const InputDecoration(labelText: 'Opens (HH:mm)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _closeController, decoration: const InputDecoration(labelText: 'Closes (HH:mm)'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _durationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Slot length (min)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _capacityController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity per slot'))),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loading ? null : () => _submit(hospitalId), child: const Text('Add Department')),
            const Divider(height: 32),
            Text('Existing departments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder(
                stream: departmentsAsync,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final depts = snap.data!;
                  return ListView.builder(
                    itemCount: depts.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(depts[i].name),
                      subtitle: Text('${depts[i].openTime}–${depts[i].closeTime} · ${depts[i].slotDurationMinutes}min slots · capacity ${depts[i].slotCapacity}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}