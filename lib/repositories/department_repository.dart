import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/department_model.dart';

class DepartmentRepository {
  DepartmentRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Future<void> createDepartment({
    required String hospitalId,
    required String name,
    String openTime = '08:00',
    String closeTime = '17:00',
    int slotDurationMinutes = 30,
    int slotCapacity = 5,
  }) async {
    try {
      await _client.from('departments').insert(
            DepartmentModel(
              id: '',
              hospitalId: hospitalId,
              name: name,
              openTime: openTime,
              closeTime: closeTime,
              slotDurationMinutes: slotDurationMinutes,
              slotCapacity: slotCapacity,
            ).toInsert(),
          );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Stream<List<DepartmentModel>> watchDepartments(String hospitalId) {
    return _client
        .from('departments')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map((rows) => rows.map(DepartmentModel.fromSupabase).toList());
  }

  /// Unscoped list — for super_admin dashboards only. RLS still applies;
  /// non–super-admin callers only see rows their policies allow (typically
  /// none for a full unscoped read of other hospitals' departments).
  Stream<List<DepartmentModel>> watchAllDepartments() {
    return _client
        .from('departments')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.map(DepartmentModel.fromSupabase).toList());
  }

  /// Resolves a department name from an id given a list already fetched
  /// elsewhere (e.g. from watchDepartments).
  String departmentNameFromList(List<DepartmentModel> departments, String departmentId) {
    final match = departments.where((d) => d.id == departmentId);
    return match.isEmpty ? departmentId : match.first.name;
  }

  Map<String, String> departmentNameMap(List<DepartmentModel> departments) {
    return {for (final d in departments) d.id: d.name};
  }
}
