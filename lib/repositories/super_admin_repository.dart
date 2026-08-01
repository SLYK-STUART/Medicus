import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_init.dart';
import '../models/appointment_model.dart';
import '../models/department_model.dart';
import '../models/doctor_model.dart';
import '../models/user_model.dart';
import 'appointment_repository.dart';
import 'department_repository.dart';
import 'doctor_repository.dart';

/// Platform-wide, unscoped queries — only safe to call as super_admin.
/// All of these streams now read from Supabase (profiles + reference data).
class SuperAdminRepository {
  SuperAdminRepository({
    SupabaseClient? client,
    DepartmentRepository? departmentRepository,
    DoctorRepository? doctorRepository,
    AppointmentRepository? appointmentRepository,
  })  : _client = client ?? supabase,
        _departmentRepository = departmentRepository ?? DepartmentRepository(),
        _doctorRepository = doctorRepository ?? DoctorRepository(),
        _appointmentRepository = appointmentRepository ?? AppointmentRepository();

  final SupabaseClient _client;
  final DepartmentRepository _departmentRepository;
  final DoctorRepository _doctorRepository;
  final AppointmentRepository _appointmentRepository;

  Stream<List<UserModel>> watchAllUsers() {
    return _client.from('profiles').stream(primaryKey: ['id']).map(
          (rows) => rows.map(UserModel.fromSupabase).toList(),
    );
  }

  Stream<List<DepartmentModel>> watchAllDepartments() {
    return _departmentRepository.watchAllDepartments();
  }

  Stream<List<DoctorModel>> watchAllDoctors() {
    return _doctorRepository.watchAllDoctors();
  }

  Stream<List<AppointmentModel>> watchAllAppointmentsForDate(String date) {
    return _appointmentRepository.watchAllAppointmentsForDate(date);
  }
}
