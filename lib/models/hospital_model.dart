class HospitalModel {
  final String id;
  final String name;
  final String address;
  final String? contactInfo;
  final String skipPolicy;
  final int noShowGraceMinutes;

  const HospitalModel({
    required this.id,
    required this.name,
    required this.address,
    this.contactInfo,
    this.skipPolicy = 'end_of_queue',
    this.noShowGraceMinutes = 5,
  });

  factory HospitalModel.fromSupabase(Map<String, dynamic> data) {
    return HospitalModel(
      id: data['id'] as String,
      name: data['name'] as String,
      address: data['address'] as String,
      contactInfo: data['contact_info'] as String?,
      skipPolicy: data['skip_policy'] as String? ?? 'end_of_queue',
      noShowGraceMinutes: (data['no_show_grace_minutes'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic> toInsert() => {
        'name': name,
        'address': address,
        'contact_info': contactInfo,
        'skip_policy': skipPolicy,
        'no_show_grace_minutes': noShowGraceMinutes,
      };
}
