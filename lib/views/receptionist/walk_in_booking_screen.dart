import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/department_model.dart';
import '../../repositories/walkin_booking_helper.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import 'checkin_screen.dart'; // queueRepositoryProvider

class WalkInBookingScreen extends ConsumerStatefulWidget {
  const WalkInBookingScreen({super.key});
  @override
  ConsumerState<WalkInBookingScreen> createState() => _WalkInBookingScreenState();
}

class _WalkInBookingScreenState extends ConsumerState<WalkInBookingScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _departmentId;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit(String hospitalId) async {
    if (_nameController.text.trim().isEmpty || _departmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and department are required')));
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
        priority: 'normal',
      );

      if (mounted) {
        _nameController.clear();
        _phoneController.clear();
        setState(() => _departmentId = null);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Patient Checked In'),
            content: Text('Token #$tokenNumber — added to the live queue.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    return Scaffold(
      appBar: AppBar(title: const Text('Book Walk-In Patient')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'For patients without a smartphone. Books and checks them into the live queue immediately.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Patient full name')),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number (optional, enables SMS updates)'),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<DepartmentModel>>(
              stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
              builder: (context, snap) {
                final depts = snap.data ?? [];
                return DropdownButtonFormField<String>(
                  initialValue: _departmentId,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                  onChanged: (v) => setState(() => _departmentId = v),
                );
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.person_add),
              label: Text(_submitting ? 'Processing...' : 'Book & Check In'),
              onPressed: _submitting ? null : () => _submit(hospitalId),
            ),
          ],
        ),
      ),
    );
  }
}