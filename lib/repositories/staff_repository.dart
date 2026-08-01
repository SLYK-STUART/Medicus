import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';

class StaffRepository {
  StaffRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Future<String> createStaffAccount({
    required String email,
    required String password,
    required String role,
    String? displayName,
    String? hospitalId,
    String? departmentId,
    String? roomNumber,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-staff-account',
        body: {
          'email': email,
          'password': password,
          'displayName': displayName,
          'role': role,
          'hospitalId': hospitalId,
          'departmentId': departmentId,
          'roomNumber': roomNumber,
        },
      );

      final data = _asMap(response.data);

      if (response.status != 200) {
        throw AuthFailure(
          data['error'] as String? ?? 'Failed to create staff account',
          code: data['code'] as String? ?? 'error',
        );
      }

      final uid = data['uid'] as String?;
      if (uid == null) {
        throw const AuthFailure('Staff created but no uid returned', code: 'no-uid');
      }
      return uid;
    } on AuthFailure {
      rethrow;
    } on FunctionException catch (e) {
      final details = _asMap(e.details);
      throw AuthFailure(
        details['error'] as String? ?? e.reasonPhrase ?? 'Failed to create staff account',
        code: details['code'] as String? ?? e.status.toString(),
      );
    } catch (e) {
      throw AuthFailure(e.toString(), code: 'create-staff-failed');
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
