import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/department_model.dart';
import '../../models/doctor_model.dart';
import '../../repositories/doctor_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

final _doctorRepoProvider = Provider((ref) => DoctorRepository());

class DoctorListScreen extends ConsumerWidget {
  const DoctorListScreen({super.key});

  Future<void> _editRoomNumber(BuildContext context, WidgetRef ref, DoctorModel doctor) async {
    final controller = TextEditingController(text: doctor.roomNumber ?? '');
    final newRoom = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Room Number'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Room number')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newRoom == null || !context.mounted) return;
    try {
      await ref.read(_doctorRepoProvider).updateRoomNumber(doctorId: doctor.uid, roomNumber: newRoom);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    return Scaffold(
      appBar: AppBar(title: const Text('Doctors')),
      body: StreamBuilder<List<DepartmentModel>>(
        stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(hospitalId),
        builder: (context, deptSnap) {
          final departments = deptSnap.data ?? [];
          final deptNameById = {for (final d in departments) d.id: d.name};

          return StreamBuilder<List<DoctorModel>>(
            stream: ref.read(_doctorRepoProvider).watchAllDoctorsForHospital(hospitalId),
            builder: (context, docSnap) {
              if (docSnap.hasError) return Center(child: Text('Error: ${docSnap.error}'));
              if (!docSnap.hasData) return const Center(child: CircularProgressIndicator());
              final doctors = docSnap.data!;
              if (doctors.isEmpty) return const Center(child: Text('No doctors yet'));

              return ListView.builder(
                itemCount: doctors.length,
                itemBuilder: (context, i) {
                  final doc = doctors[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.medical_services)),
                    title: Text(doc.displayName),
                    subtitle: Text(
                      '${deptNameById[doc.departmentId] ?? 'Unknown department'} · '
                          '${doc.roomNumber?.isNotEmpty == true ? 'Room ${doc.roomNumber}' : 'No room set'} · '
                          'avg ${doc.avgConsultationMinutes} min/consult',
                    ),
                    onTap: () => _editRoomNumber(context, ref, doc),
                    trailing: departments.isEmpty
                        ? null
                        : DropdownButton<String>(
                      value: doc.departmentId,
                      items: departments
                          .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                          .toList(),
                      onChanged: (newDeptId) async {
                        if (newDeptId == null || newDeptId == doc.departmentId) return;
                        try {
                          await ref.read(_doctorRepoProvider).reassignDepartment(
                            doctorId: doc.uid,
                            newDepartmentId: newDeptId,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${doc.displayName} moved to ${deptNameById[newDeptId]}')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                          }
                        }
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}