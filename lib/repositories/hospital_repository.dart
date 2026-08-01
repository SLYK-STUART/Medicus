import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/hospital_model.dart';

export '../models/hospital_model.dart' show HospitalModel;

class HospitalRepository {
  HospitalRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Future<String> createHospital({
    required String name,
    required String address,
    String? contactInfo,
  }) async {
    try {
      final hospital = HospitalModel(
        id: '',
        name: name,
        address: address,
        contactInfo: contactInfo,
      );
      final row = await _client
          .from('hospitals')
          .insert(hospital.toInsert())
          .select('id')
          .single();
      return row['id'] as String;
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Stream<List<HospitalModel>> watchHospitals() {
    return _client.from('hospitals').stream(primaryKey: ['id']).map((rows) {
      final list = rows.map(HospitalModel.fromSupabase).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Stream<HospitalModel?> watchHospital(String hospitalId) {
    return _client
        .from('hospitals')
        .stream(primaryKey: ['id'])
        .eq('id', hospitalId)
        .map((rows) => rows.isEmpty ? null : HospitalModel.fromSupabase(rows.first));
  }

  Future<void> updateSkipPolicy({
    required String hospitalId,
    required String skipPolicy,
  }) async {
    try {
      await _client.from('hospitals').update({'skip_policy': skipPolicy}).eq('id', hospitalId);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> updateNoShowGraceMinutes({
    required String hospitalId,
    required int minutes,
  }) async {
    try {
      await _client
          .from('hospitals')
          .update({'no_show_grace_minutes': minutes})
          .eq('id', hospitalId);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }
}
