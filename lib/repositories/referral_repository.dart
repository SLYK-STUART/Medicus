import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';

class ReferralRepository {
  ReferralRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Future<({String appointmentId, int tokenNumber, String visitId})> createReferral({
    required String originAppointmentId,
    required String targetDepartmentId,
  }) async {
    try {
      final result = await _client.rpc(
        'create_referral',
        params: {
          'p_origin_appointment_id': originAppointmentId,
          'p_target_department_id': targetDepartmentId,
        },
      );
      final row = _firstRow(result);
      if (row == null) {
        throw const DataFailure('Referral returned no result', code: 'empty-result');
      }
      return (
        appointmentId: row['appointment_id'] as String,
        tokenNumber: (row['token_number'] as num).toInt(),
        visitId: row['visit_id'] as String,
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<({String appointmentId, String scheduledDate, int tokenNumber})> createFollowUp({
    required String originAppointmentId,
    required int daysFromNow,
  }) async {
    try {
      final result = await _client.rpc(
        'create_follow_up',
        params: {
          'p_origin_appointment_id': originAppointmentId,
          'p_days_from_now': daysFromNow,
        },
      );
      final row = _firstRow(result);
      if (row == null) {
        throw const DataFailure('Follow-up returned no result', code: 'empty-result');
      }
      final scheduled = row['scheduled_date'];
      return (
        appointmentId: row['appointment_id'] as String,
        scheduledDate: scheduled is String
            ? (scheduled.length >= 10 ? scheduled.substring(0, 10) : scheduled)
            : scheduled.toString(),
        tokenNumber: (row['token_number'] as num).toInt(),
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Map<String, dynamic>? _firstRow(dynamic result) {
    if (result == null) return null;
    if (result is List) {
      if (result.isEmpty) return null;
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }
}
