import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/appointment_repository.dart';
import '../../repositories/department_repository.dart';
import '../../repositories/doctor_repository.dart';
import '../../repositories/hospital_repository.dart';

final bookingHospitalRepoProvider = Provider((ref) => HospitalRepository());
final bookingDepartmentRepoProvider = Provider((ref) => DepartmentRepository());
final bookingDoctorRepoProvider = Provider((ref) => DoctorRepository());
final appointmentRepositoryProvider = Provider((ref) => AppointmentRepository());

class BookingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<({String appointmentId, int tokenNumber})?> book({
    String? patientId,
    required String hospitalId,
    required String departmentId,
    required String scheduledDate,
    String? scheduledTimeSlot,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(appointmentRepositoryProvider).createAppointment(
        patientId: patientId,
        hospitalId: hospitalId,
        departmentId: departmentId,
        scheduledDate: scheduledDate,
        scheduledTimeSlot: scheduledTimeSlot,
      );
      state = const AsyncData(null);
      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final bookingControllerProvider = AsyncNotifierProvider<BookingController, void>(BookingController.new);