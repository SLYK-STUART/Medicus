import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/notification_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../patient/notifications_screen.dart'; // notificationRepositoryProvider

class ReceptionistNotificationsScreen extends ConsumerWidget {
  const ReceptionistNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: StreamBuilder<List<NotificationModel>>(
          stream: ref.read(notificationRepositoryProvider).watchMyNotifications(profile.uid),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final notifications = snap.data!;
            if (notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('No notifications', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final n = notifications[i];
                final isPhoneWarning = n.type == 'walkin_no_phone';
                return Card(
                  color: n.read ? Colors.white : AppColors.surfaceVariant.withValues(alpha: 0.6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isPhoneWarning ? AppColors.urgent.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15),
                      child: Icon(
                        isPhoneWarning ? Icons.phone_disabled_outlined : Icons.info_outline,
                        color: isPhoneWarning ? AppColors.urgent : AppColors.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(n.message, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.w600)),
                    subtitle: n.createdAt != null
                        ? Text(DateFormat('MMM d, h:mm a').format(n.createdAt!), style: const TextStyle(fontSize: 12))
                        : null,
                    onTap: () {
                      if (!n.read) ref.read(notificationRepositoryProvider).markAsRead(n.id);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}