import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/appointment_model.dart';

class AppointmentRepository {
  AppointmentRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Future<({String appointmentId, int tokenNumber})> createAppointment({
    String? patientId,
    required String hospitalId,
    required String departmentId,
    String? doctorId,
    required String scheduledDate,
    String? scheduledTimeSlot,
  }) async {
    try {
      final result = await _client.rpc(
        'create_appointment',
        params: {
          'p_hospital_id': hospitalId,
          'p_department_id': departmentId,
          'p_scheduled_date': scheduledDate,
          'p_patient_id': patientId,
          'p_doctor_id': doctorId,
          'p_scheduled_time_slot': scheduledTimeSlot,
        },
      );

      final row = _firstRow(result);
      if (row == null) {
        throw const DataFailure('Booking returned no result', code: 'empty-result');
      }
      return (
        appointmentId: row['appointment_id'] as String,
        tokenNumber: (row['token_number'] as num).toInt(),
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<AppointmentModel?> fetchAppointmentById(String appointmentId) async {
    try {
      final data = await _client.from('appointments').select().eq('id', appointmentId).maybeSingle();
      if (data == null) return null;
      return AppointmentModel.fromSupabase(data);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Future<List<({String slot, int remaining, int capacity})>> getAvailableSlots({
    required String hospitalId,
    required String departmentId,
    required String date,
  }) async {
    try {
      final result = await _client.rpc(
        'get_available_slots',
        params: {
          'p_hospital_id': hospitalId,
          'p_department_id': departmentId,
          'p_date': date,
        },
      );

      final rows = _asList(result);
      return rows
          .map(
            (s) => (
              slot: s['slot'] as String,
              remaining: (s['remaining'] as num).toInt(),
              capacity: (s['capacity'] as num?)?.toInt() ?? 5,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Stream<List<AppointmentModel>> watchPatientAppointments(String patientId) {
    return _client
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('patient_id', patientId)
        .map((rows) {
      final appts = rows.map(AppointmentModel.fromSupabase).toList();
      appts.sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
      return appts;
    });
  }

  Stream<Map<String, int>> watchTodaysStatsForHospital({
    required String hospitalId,
    required String date,
  }) {
    return watchTodaysAppointmentsForHospital(hospitalId: hospitalId, date: date).map((appts) {
      final counts = <String, int>{
        'booked': 0,
        'checked_in': 0,
        'completed': 0,
        'skipped': 0,
      };
      for (final a in appts) {
        counts[a.status] = (counts[a.status] ?? 0) + 1;
      }
      return counts;
    });
  }

  Stream<List<AppointmentModel>> watchDoctorAppointmentHistory({
    required String doctorId,
    required String hospitalId,
  }) {
    return _client
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map((rows) {
      final appts = rows
          .where((r) => r['doctor_id'] == doctorId)
          .map(AppointmentModel.fromSupabase)
          .toList();
      appts.sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
      return appts;
    });
  }

  Stream<List<AppointmentModel>> watchAppointmentsBookedBy({
    required String uid,
    required String hospitalId,
  }) {
    return _client
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map((rows) {
      final appts = rows
          .where((r) => r['booked_by'] == uid)
          .map(AppointmentModel.fromSupabase)
          .toList();
      appts.sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
      return appts;
    });
  }

  Stream<List<AppointmentModel>> watchTodaysAppointments({
    required String hospitalId,
    required String departmentId,
    required String date,
  }) {
    return watchTodaysAppointmentsForHospital(hospitalId: hospitalId, date: date).map(
      (appts) => appts.where((a) => a.departmentId == departmentId).toList(),
    );
  }

  Stream<List<AppointmentModel>> watchTodaysAppointmentsForHospital({
    required String hospitalId,
    required String date,
  }) {
    return _client
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('hospital_id', hospitalId)
        .map(
          (rows) => rows
              .where((r) => AppointmentModel.fromSupabase(r).scheduledDate == date)
              .map(AppointmentModel.fromSupabase)
              .toList(),
        );
  }

  Stream<List<AppointmentModel>> watchAllAppointmentsForDate(String date) {
    return _client.from('appointments').stream(primaryKey: ['id']).map(
          (rows) => rows
              .where((r) => AppointmentModel.fromSupabase(r).scheduledDate == date)
              .map(AppointmentModel.fromSupabase)
              .toList(),
        );
  }

  Map<String, dynamic>? _firstRow(dynamic result) {
    final list = _asList(result);
    if (list.isEmpty) return null;
    return list.first;
  }

  List<Map<String, dynamic>> _asList(dynamic result) {
    if (result == null) return [];
    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (result is Map) return [Map<String, dynamic>.from(result)];
    return [];
  }
}
