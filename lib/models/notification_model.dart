class NotificationModel {
  final String id;
  final String type;
  final String message;
  final bool read;
  final DateTime? createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.message,
    required this.read,
    this.createdAt,
  });

  factory NotificationModel.fromSupabase(Map<String, dynamic> data) {
    return NotificationModel(
      id: data['id'] as String,
      type: (data['type'] as String?) ?? 'info',
      message: (data['message'] as String?) ?? '',
      read: data['read'] as bool? ?? false,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'] as String)
          : null,
    );
  }
}
