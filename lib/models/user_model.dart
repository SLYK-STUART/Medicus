enum AppRole {
  superAdmin,
  hospitalAdmin,
  receptionist,
  doctor,
  patient;

  static AppRole fromString(String value) {
    switch (value) {
      case 'super_admin':
        return AppRole.superAdmin;
      case 'hospital_admin':
        return AppRole.hospitalAdmin;
      case 'receptionist':
        return AppRole.receptionist;
      case 'doctor':
        return AppRole.doctor;
      case 'patient':
        return AppRole.patient;
      default:
        throw ArgumentError('Unknown role string: $value');
    }
  }

  String toDbString() {
    switch (this) {
      case AppRole.superAdmin:
        return 'super_admin';
      case AppRole.hospitalAdmin:
        return 'hospital_admin';
      case AppRole.receptionist:
        return 'receptionist';
      case AppRole.doctor:
        return 'doctor';
      case AppRole.patient:
        return 'patient';
    }
  }
}

class UserModel {
  final String uid;
  final String? email; // null for walk-in patients created without one
  final String? displayName;
  final String? phoneNumber;
  final AppRole role;
  final String? hospitalId;
  final DateTime? createdAt;

  const UserModel({
    required this.uid,
    this.email,
    this.displayName,
    this.phoneNumber,
    required this.role,
    this.hospitalId,
    this.createdAt,
  });

  factory UserModel.fromSupabase(Map<String, dynamic> data) {
    return UserModel(
      uid: data['id'] as String,
      email: data['email'] as String?,
      displayName: data['display_name'] as String?,
      phoneNumber: data['phone_number'] as String?,
      role: AppRole.fromString(data['role'] as String),
      hospitalId: data['hospital_id'] as String?,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'] as String)
          : null,
    );
  }

  /// Insert payload for `public.profiles` (snake_case columns).
  Map<String, dynamic> toProfileInsert() {
    return {
      'id': uid,
      'email': email,
      'display_name': displayName,
      'phone_number': phoneNumber,
      'role': role.toDbString(),
      'hospital_id': hospitalId,
    };
  }

  UserModel copyWith({String? displayName, String? phoneNumber, AppRole? role, String? hospitalId}) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      hospitalId: hospitalId ?? this.hospitalId,
      createdAt: createdAt,
    );
  }
}
