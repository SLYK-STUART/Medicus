import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import 'appointment_repository.dart';
import 'queue_repository.dart';

class WalkInBookingHelper {
  WalkInBookingHelper({
    required AppointmentRepository appointmentRepository,
    required QueueRepository queueRepository,
    SupabaseClient? client,
  })  : _appointmentRepository = appointmentRepository,
        _queueRepository = queueRepository,
        _client = client ?? supabase;

  final AppointmentRepository _appointmentRepository;
  final QueueRepository _queueRepository;
  final SupabaseClient _client;

  /// Shared by walk-in booking and priority check-in emergency walk-in tab.
  Future<int> bookAndCheckIn({
    required String displayName,
    String? phoneNumber,
    required String hospitalId,
    required String departmentId,
    required String priority,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-walk-in-patient',
        body: {
          'displayName': displayName,
          'phoneNumber': phoneNumber,
        },
      );
      final data = _asMap(response.data);
      if (response.status != 200) {
        throw DataFailure(
          data['error'] as String? ?? 'Failed to create walk-in patient',
          code: data['code'] as String? ?? 'error',
        );
      }
      final patientId = data['uid'] as String?;
      if (patientId == null) {
        throw const DataFailure('Walk-in created but no uid returned', code: 'no-uid');
      }

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final appointmentResult = await _appointmentRepository.createAppointment(
        patientId: patientId,
        hospitalId: hospitalId,
        departmentId: departmentId,
        scheduledDate: today,
      );

      await _queueRepository.checkIn(
        patientName: displayName,
        patientPhoneNumber: phoneNumber,
        appointmentId: appointmentResult.appointmentId,
        patientId: patientId,
        tokenNumber: appointmentResult.tokenNumber,
        hospitalId: hospitalId,
        date: today,
        departmentId: departmentId,
        priority: priority,
      );

      return appointmentResult.tokenNumber;
    } on DataFailure {
      rethrow;
    } on FunctionException catch (e) {
      final details = _asMap(e.details);
      throw DataFailure(
        details['error'] as String? ?? e.reasonPhrase ?? 'Failed to create walk-in patient',
        code: details['code'] as String? ?? e.status.toString(),
      );
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }
}
