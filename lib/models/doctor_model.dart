class DoctorModel {
  final String uid;
  final String displayName;
  final String hospitalId;
  final String departmentId;
  final String? roomNumber;
  final int avgConsultationMinutes;

  const DoctorModel({
    required this.uid,
    required this.displayName,
    required this.hospitalId,
    required this.departmentId,
    this.roomNumber,
    required this.avgConsultationMinutes,
  });

  factory DoctorModel.fromSupabase(Map<String, dynamic> data) {
    return DoctorModel(
      uid: data['id'] as String,
      displayName: (data['display_name'] as String?) ?? 'Unnamed',
      hospitalId: data['hospital_id'] as String,
      departmentId: data['department_id'] as String,
      roomNumber: data['room_number'] as String?,
      avgConsultationMinutes: (data['avg_consultation_minutes'] as num?)?.toInt() ?? 15,
    );
  }
}
