import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/department_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/super_admin/staff_management_viewmodel.dart';

final _departmentRepoProvider = Provider((ref) => DepartmentRepository());

class StaffCreateScreen extends ConsumerStatefulWidget {
  const StaffCreateScreen({super.key});
  @override
  ConsumerState<StaffCreateScreen> createState() => _StaffCreateScreenState();
}

class _StaffCreateScreenState extends ConsumerState<StaffCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'receptionist';
  String? _selectedDepartmentId;
  final _roomController = TextEditingController();


  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == 'doctor' && _selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a department for the doctor')));
      return;
    }

    final success = await ref.read(staffCreateControllerProvider.notifier).create(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      role: _selectedRole,
      displayName: _nameController.text.trim(),
      departmentId: _selectedRole == 'doctor' ? _selectedDepartmentId : null,
      roomNumber: _selectedRole == 'doctor' ? _roomController.text.trim() : null,
    );

    if (success && mounted) {
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _roomController.clear();
      setState(() => _selectedDepartmentId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedRole == 'doctor' ? 'Doctor' : 'Receptionist'} account created')));
    } else if (!success && mounted) {
      final error = ref.read(staffCreateControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error?.toString() ?? 'Failed to create account')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(staffCreateControllerProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Staff Member')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'receptionist', label: Text('Receptionist')),
                  ButtonSegment(value: 'doctor', label: Text('Doctor')),
                ],
                selected: {_selectedRole},
                onSelectionChanged: (s) => setState(() => _selectedRole = s.first),
              ),
              if (_selectedRole == 'doctor' && hospitalId != null) ...[
                const SizedBox(height: 12),
                StreamBuilder(
                  stream: ref.read(_departmentRepoProvider).watchDepartments(hospitalId),
                  builder: (context, snap) {
                    final depts = snap.data ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedDepartmentId,
                      decoration: const InputDecoration(labelText: 'Department'),
                      items: depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                      onChanged: (v) => setState(() => _selectedDepartmentId = v),
                    );
                  },
                ),
              ],
              if (_selectedRole == 'doctor') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(labelText: 'Room number', prefixIcon: Icon(Icons.meeting_room_outlined)),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Temporary password'),
                validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: createState.isLoading ? null : _submit,
                child: createState.isLoading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}