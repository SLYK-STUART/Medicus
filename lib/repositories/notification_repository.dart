import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/failures.dart';
import '../core/supabase/supabase_init.dart';
import '../models/notification_model.dart';

class NotificationRepository {
  NotificationRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// Live notifications for a user. Sorted client-side by created_at desc.
  Stream<List<NotificationModel>> watchMyNotifications(String userId) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) {
      final list = rows.map(NotificationModel.fromSupabase).toList();
      list.sort(
        (a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
      return list;
    });
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _client.from('notifications').update({'read': true}).eq('id', notificationId);
    } on PostgrestException catch (e) {
      throw DataFailure(e.message, code: e.code);
    }
  }
}
