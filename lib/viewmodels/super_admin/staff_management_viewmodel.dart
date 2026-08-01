import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) => StaffRepository());

class StaffCreateController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> create({
    required String email,
    required String password,
    required String role,
    String? displayName,
    String? hospitalId,
    String? departmentId,
    String? roomNumber,
  }) async {
    state = const AsyncLoading();
    try {
      await ref.read(staffRepositoryProvider).createStaffAccount(
        email: email,
        password: password,
        role: role,
        displayName: displayName,
        hospitalId: hospitalId,
        departmentId: departmentId,
        roomNumber: roomNumber,
      );
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final staffCreateControllerProvider = AsyncNotifierProvider<StaffCreateController, void>(StaffCreateController.new);