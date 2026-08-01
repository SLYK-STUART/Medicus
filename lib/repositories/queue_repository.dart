import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/queue_entry_model.dart';

class QueueRepository {
  QueueRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  static const _activeStatuses = ['waiting', 'called', 'in_consultation'];

  /// Patient's own visit may also be paused mid-consultation.
  static const _myVisitStatuses = ['waiting', 'called', 'in_consultation', 'paused'];

  /// Transactional check-in: inserts queue_entries + sets appointment checked_in.
  /// FIX (vs Firebase): no longer a non-atomic dual-write across two stores.
  Future<String> checkIn({
    required String appointmentId,
    required String patientId,
    required String patientName,
    String? patientPhoneNumber,
    String? doctorId,
    required int tokenNumber,
    required String hospitalId,
    required String date,
    required String departmentId,
    String priority = 'normal',
  }) async {
    try {
      final result = await _client.rpc(
        'check_in',
        params: {
          'p_appointment_id': appointmentId,
          'p_hospital_id': hospitalId,
          'p_department_id': departmentId,
          'p_date': date,
          'p_priority': priority,
          'p_doctor_id': (doctorId == null || doctorId.isEmpty) ? null : doctorId,
        },
      );
      // patientId/patientName/tokenNumber are taken from the appointment server-side.
      return result as String;
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> updateStatus({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
    required String status,
  }) async {
    try {
      await _client.rpc(
        'update_queue_status',
        params: {
          'p_entry_id': entryId,
          'p_new_status': status,
        },
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> markSkipped({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
  }) async {
    try {
      await _client.rpc('mark_queue_skipped', params: {'p_entry_id': entryId});
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> escalatePriority({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
    required String newPriority,
  }) async {
    try {
      await _client.from('queue_entries').update({'priority': newPriority}).eq('id', entryId);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<({String entryId, int tokenNumber})> callNextPatient({
    required String hospitalId,
    required String date,
  }) async {
    try {
      final result = await _client.rpc(
        'call_next_patient',
        params: {
          'p_hospital_id': hospitalId,
          'p_date': date,
        },
      );
      final row = _firstRow(result);
      if (row == null) {
        throw const DataFailure('No patients waiting.', code: 'P0002');
      }
      return (
        entryId: row['entry_id'] as String,
        tokenNumber: (row['token_number'] as num).toInt(),
      );
    } on PostgrestException catch (e) {
      if (e.code == 'P0002' || e.message.contains('No patients waiting')) {
        throw const DataFailure('No patients waiting.', code: 'not-found');
      }
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<({int graceMinutes, int graceDeadlineMillis})> warnPatientDelay({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
  }) async {
    try {
      final result = await _client.rpc(
        'warn_patient_delay',
        params: {'p_entry_id': entryId},
      );
      final row = _firstRow(result);
      if (row == null) {
        throw const DataFailure('Failed to warn patient', code: 'empty-result');
      }
      return (
        graceMinutes: (row['grace_minutes'] as num).toInt(),
        graceDeadlineMillis: (row['grace_deadline_millis'] as num).toInt(),
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> rejoinPatient({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
    required String skipPolicy,
    required String priority,
  }) async {
    try {
      await _client.rpc(
        'rejoin_patient',
        params: {
          'p_entry_id': entryId,
          'p_skip_policy': skipPolicy,
        },
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> pauseConsultation({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
  }) async {
    try {
      await _client.rpc(
        'update_queue_status',
        params: {
          'p_entry_id': entryId,
          'p_new_status': 'paused',
        },
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<void> resumeConsultation({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String entryId,
  }) async {
    try {
      await _client.rpc('resume_consultation', params: {'p_entry_id': entryId});
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Stream<List<QueueEntryModel>> watchLiveQueue({
    required String hospitalId,
    required String date,
    required String departmentId,
  }) {
    return _client
        .from('queue_entries')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map((rows) {
      final entries = rows
          .where(
            (r) =>
                r['department_id'] == departmentId &&
                _dateMatches(r['date'], date) &&
                _activeStatuses.contains(r['status']),
          )
          .map(QueueEntryModel.fromSupabase)
          .toList();
      const priorityRank = {'critical': 0, 'urgent': 1, 'normal': 2};
      entries.sort((a, b) {
        final byPriority = priorityRank[a.priority]!.compareTo(priorityRank[b.priority]!);
        if (byPriority != 0) return byPriority;
        final aAt = a.checkedInAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = b.checkedInAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aAt.compareTo(bAt);
      });
      return entries;
    });
  }

  Stream<int> watchCompletedCountForDoctorToday({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String doctorId,
  }) {
    return _client
        .from('queue_entries')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map(
          (rows) => rows
              .where(
                (r) =>
                    r['department_id'] == departmentId &&
                    _dateMatches(r['date'], date) &&
                    r['doctor_id'] == doctorId &&
                    r['status'] == 'completed',
              )
              .length,
        );
  }

  Stream<List<QueueEntryModel>> watchSkippedEntries({
    required String hospitalId,
    required String date,
    required String departmentId,
  }) {
    return _client
        .from('queue_entries')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map(
          (rows) => rows
              .where(
                (r) =>
                    r['department_id'] == departmentId &&
                    _dateMatches(r['date'], date) &&
                    r['status'] == 'skipped',
              )
              .map(QueueEntryModel.fromSupabase)
              .toList(),
        );
  }

  Stream<QueueEntryModel?> watchMyQueueStatus({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String patientId,
  }) {
    return _client
        .from('queue_entries')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map((rows) {
      final match = rows.where(
        (r) =>
            r['department_id'] == departmentId &&
            _dateMatches(r['date'], date) &&
            r['patient_id'] == patientId &&
            _myVisitStatuses.contains(r['status']),
      );
      if (match.isEmpty) return null;
      return QueueEntryModel.fromSupabase(match.first);
    });
  }

  Stream<List<QueueEntryModel>> watchPausedEntriesForDoctor({
    required String hospitalId,
    required String date,
    required String departmentId,
    required String doctorId,
  }) {
    return _client
        .from('queue_entries')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map(
          (rows) => rows
              .where(
                (r) =>
                    r['department_id'] == departmentId &&
                    _dateMatches(r['date'], date) &&
                    r['doctor_id'] == doctorId &&
                    r['status'] == 'paused',
              )
              .map(QueueEntryModel.fromSupabase)
              .toList(),
        );
  }

  bool _dateMatches(dynamic value, String date) {
    if (value is String) return value.length >= 10 ? value.substring(0, 10) == date : value == date;
    return value.toString() == date;
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
