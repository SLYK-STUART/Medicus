class AppointmentModel {
  final String id;
  final String patientId;
  final String patientName;
  final String? patientPhoneNumber;
  final String hospitalId;
  final String departmentId;
  final String? doctorId;
  final String scheduledDate;
  final String? scheduledTimeSlot;
  final int tokenNumber;
  final String status;
  final String? visitId;
  final bool isRecurring;
  final String? recurringParentId;
  final String bookedBy;
  final DateTime? checkedInAt;
  final String source;

  const AppointmentModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientPhoneNumber,
    required this.hospitalId,
    required this.departmentId,
    this.doctorId,
    required this.scheduledDate,
    this.scheduledTimeSlot,
    required this.tokenNumber,
    required this.status,
    this.visitId,
    required this.isRecurring,
    this.recurringParentId,
    required this.bookedBy,
    this.checkedInAt,
    this.source = 'patient_booking',
  });

  factory AppointmentModel.fromSupabase(Map<String, dynamic> data) {
    return AppointmentModel(
      id: data['id'] as String,
      patientId: data['patient_id'] as String,
      patientName: (data['patient_name'] as String?) ?? 'Unknown',
      patientPhoneNumber: data['patient_phone_number'] as String?,
      hospitalId: data['hospital_id'] as String,
      departmentId: data['department_id'] as String,
      doctorId: data['doctor_id'] as String?,
      scheduledDate: _dateToString(data['scheduled_date']),
      scheduledTimeSlot: data['scheduled_time_slot'] as String?,
      tokenNumber: (data['token_number'] as num).toInt(),
      status: data['status'] as String,
      visitId: data['visit_id'] as String?,
      isRecurring: data['is_recurring'] as bool? ?? false,
      recurringParentId: data['recurring_parent_id'] as String?,
      bookedBy: data['booked_by'] as String,
      checkedInAt: data['checked_in_at'] != null
          ? DateTime.tryParse(data['checked_in_at'] as String)
          : null,
      source: (data['source'] as String?) ?? 'patient_booking',
    );
  }

  static String _dateToString(dynamic value) {
    if (value is String) return value.length >= 10 ? value.substring(0, 10) : value;
    return value.toString();
  }
}
