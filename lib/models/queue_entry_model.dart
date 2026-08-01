class QueueEntryModel {
  final String id;
  final String appointmentId;
  final String patientId;
  final String patientName;
  final String? patientPhoneNumber;
  final String doctorId;
  final int tokenNumber;
  final DateTime? checkedInAt;
  final DateTime? consultationStartedAt;
  final DateTime? warnedAt;
  final DateTime? graceDeadline;
  final String priority;
  final String status;
  final String lastNotifiedThreshold;
  final int? patientsAhead;

  const QueueEntryModel({
    required this.id,
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
    this.patientPhoneNumber,
    required this.doctorId,
    required this.tokenNumber,
    this.checkedInAt,
    this.consultationStartedAt,
    this.warnedAt,
    this.graceDeadline,
    required this.priority,
    required this.status,
    this.lastNotifiedThreshold = 'none',
    this.patientsAhead,
  });

  factory QueueEntryModel.fromSupabase(Map<String, dynamic> data) {
    return QueueEntryModel(
      id: data['id'] as String,
      appointmentId: data['appointment_id'] as String,
      patientId: data['patient_id'] as String,
      patientName: (data['patient_name'] as String?) ?? 'Unknown',
      patientPhoneNumber: data['patient_phone_number'] as String?,
      doctorId: (data['doctor_id'] as String?) ?? '',
      tokenNumber: (data['token_number'] as num).toInt(),
      checkedInAt: _parseTs(data['checked_in_at']),
      consultationStartedAt: _parseTs(data['consultation_started_at']),
      warnedAt: _parseTs(data['warned_at']),
      graceDeadline: _parseTs(data['grace_deadline']),
      priority: (data['priority'] as String?) ?? 'normal',
      status: (data['status'] as String?) ?? 'waiting',
      lastNotifiedThreshold: (data['last_notified_threshold'] as String?) ?? 'none',
      patientsAhead: (data['patients_ahead'] as num?)?.toInt(),
    );
  }

  static DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
