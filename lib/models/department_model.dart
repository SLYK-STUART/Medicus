class DepartmentModel {
  final String id;
  final String hospitalId;
  final String name;
  final String openTime; // 'HH:mm', 24hr
  final String closeTime;
  final int slotDurationMinutes;
  final int slotCapacity;

  const DepartmentModel({
    required this.id,
    required this.hospitalId,
    required this.name,
    this.openTime = '08:00',
    this.closeTime = '17:00',
    this.slotDurationMinutes = 30,
    this.slotCapacity = 5,
  });

  factory DepartmentModel.fromSupabase(Map<String, dynamic> data) {
    return DepartmentModel(
      id: data['id'] as String,
      hospitalId: data['hospital_id'] as String,
      name: data['name'] as String,
      openTime: _normalizeTime(data['open_time'] as String? ?? '08:00'),
      closeTime: _normalizeTime(data['close_time'] as String? ?? '17:00'),
      slotDurationMinutes: (data['slot_duration_minutes'] as num?)?.toInt() ?? 30,
      slotCapacity: (data['slot_capacity'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic> toInsert() => {
        'hospital_id': hospitalId,
        'name': name,
        'open_time': openTime,
        'close_time': closeTime,
        'slot_duration_minutes': slotDurationMinutes,
        'slot_capacity': slotCapacity,
      };

  /// Generates the list of slot labels for a day, e.g. '08:00-08:30'.
  List<String> generateSlots() {
    final slots = <String>[];
    final open = _parseTime(openTime);
    final close = _parseTime(closeTime);
    var current = open;
    while (current + slotDurationMinutes <= close) {
      final start = _formatTime(current);
      final end = _formatTime(current + slotDurationMinutes);
      slots.add('$start-$end');
      current += slotDurationMinutes;
    }
    return slots;
  }

  /// Postgres `time` may return `HH:mm:ss` — slot UI expects `HH:mm`.
  static String _normalizeTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = parts[0].padLeft(2, '0');
    final m = parts[1].padLeft(2, '0');
    return '$h:$m';
  }

  static int _parseTime(String t) {
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String _formatTime(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
