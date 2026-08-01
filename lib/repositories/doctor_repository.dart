import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/doctor_model.dart';

class DoctorRepository {
  DoctorRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Stream<List<DoctorModel>> watchDoctors({
    required String hospitalId,
    required String departmentId,
  }) {
    return _client
        .from('doctors')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map(
          (rows) => rows
              .where((r) => r['department_id'] == departmentId)
              .map(DoctorModel.fromSupabase)
              .toList(),
        );
  }

  Stream<List<DoctorModel>> watchAllDoctorsForHospital(String hospitalId) {
    return _client
        .from('doctors')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map((rows) => rows.map(DoctorModel.fromSupabase).toList());
  }

  Stream<List<DoctorModel>> watchAllDoctors() {
    return _client
        .from('doctors')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.map(DoctorModel.fromSupabase).toList());
  }

  Stream<DoctorModel?> watchMyDoctorProfile(String uid) {
    return _client
        .from('doctors')
        .stream(primaryKey: ['id'])
        .eq('id', uid)
        .map((rows) => rows.isEmpty ? null : DoctorModel.fromSupabase(rows.first));
  }

  Future<void> reassignDepartment({
    required String doctorId,
    required String newDepartmentId,
  }) async {
    try {
      await _client.from('doctors').update({'department_id': newDepartmentId}).eq('id', doctorId);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> updateRoomNumber({
    required String doctorId,
    required String roomNumber,
  }) async {
    try {
      await _client.from('doctors').update({'room_number': roomNumber}).eq('id', doctorId);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }
}
