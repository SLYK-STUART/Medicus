import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/notification_model.dart';
import '../../repositories/notification_repository.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';

final notificationRepositoryProvider = Provider((ref) => NotificationRepository());

IconData _iconForType(String type) {
  if (type.startsWith('queue_')) return Icons.timer_outlined;
  switch (type) {
    case 'called':
      return Icons.campaign_outlined;
    case 'completed':
      return Icons.check_circle_outline;
    case 'paused':
      return Icons.pause_circle_outline;
    case 'resumed':
      return Icons.play_circle_outline;
    case 'skipped':
      return Icons.skip_next_outlined;
    case 'priority_bump':
      return Icons.priority_high;
    default:
      return Icons.notifications_none;
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    if (profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () {

            },
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: ref.read(notificationRepositoryProvider).watchMyNotifications(profile.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!;

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 80,
                    color: AppColors.textSecondary.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You’ll see queue updates and alerts here',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final n = notifications[index];
              final isUnread = !n.read;

              return Card(
                elevation: isUnread ? 1 : 0,
                color: isUnread
                    ? AppColors.surfaceVariant.withOpacity(0.7)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isUnread
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surfaceVariant,
                    width: isUnread ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: isUnread
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surfaceVariant,
                    child: Icon(
                      _iconForType(n.type),
                      color: isUnread ? AppColors.primary : AppColors.textSecondary,
                      size: 24,
                    ),
                  ),
                  title: Text(
                    n.message,
                    style: TextStyle(
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                      height: 1.3,
                    ),
                  ),
                  subtitle: n.createdAt != null
                      ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('MMM d, h:mm a').format(n.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                      : null,
                  onTap: () {
                    if (isUnread) {
                      ref.read(notificationRepositoryProvider).markAsRead(n.id);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}