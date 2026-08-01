import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_init.dart';
import '../models/notification_model.dart';

/// Shows OS notification-bar alerts for every signed-in role.
///
/// Driven by Supabase Realtime on `notifications` inserts for the current
/// user — no Firebase/FCM required. Works in foreground and while the app
/// process is alive in the background.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  RealtimeChannel? _channel;
  String? _listeningUserId;
  bool _initialized = false;
  int _notificationId = 1000;

  static const _androidChannel = AndroidNotificationChannel(
    'medicare_alerts',
    'Medicare alerts',
    description: 'Queue, appointment, and account alerts',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);

    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _initialized = true;
  }

  /// Start (or restart) Realtime listening for [userId]. Call after login
  /// and whenever the auth user changes. Safe for all roles.
  Future<void> startForUser(String userId) async {
    await init();
    if (_listeningUserId == userId && _channel != null) return;

    await stop();
    _listeningUserId = userId;

    _channel = supabase
        .channel('push-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            try {
              final n = NotificationModel.fromSupabase(row);
              unawaited(_showTray(n));
            } catch (e, st) {
              debugPrint('PushNotificationService parse error: $e\n$st');
            }
          },
        )
        .subscribe();
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _listeningUserId = null;
    if (channel != null) {
      await supabase.removeChannel(channel);
    }
  }

  Future<void> _showTray(NotificationModel n) async {
    final title = _titleForType(n.type);
    await _plugin.show(
      _notificationId++,
      title,
      n.message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: n.id,
    );
  }

  String _titleForType(String type) {
    switch (type) {
      case 'called':
        return 'You\'re being called';
      case 'completed':
        return 'Consultation complete';
      case 'skipped':
        return 'Skipped from queue';
      case 'paused':
        return 'Consultation paused';
      case 'resumed':
        return 'Consultation resumed';
      case 'priority_bump':
        return 'Queue update';
      case 'queue_next':
        return 'You\'re next';
      case 'queue_fifteen_min':
        return 'Almost your turn';
      case 'queue_five_ahead':
        return 'Queue update';
      default:
        if (type.startsWith('relay_')) return 'Patient update';
        if (type.startsWith('queue_')) return 'Queue update';
        return 'Medicare';
    }
  }
}
