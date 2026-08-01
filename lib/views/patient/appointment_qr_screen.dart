import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../models/department_model.dart';
import '../../models/hospital_model.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

class AppointmentQrScreen extends ConsumerWidget {
  const AppointmentQrScreen({super.key, required this.appointment});
  final AppointmentModel appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Confirmed')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.secondary),
                  SizedBox(width: 10),
                  Text('Your appointment is confirmed', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.secondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('YOUR TOKEN', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    Text('#${appointment.tokenNumber}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceVariant),
                      ),
                      child: QrImageView(
                        data: appointment.id, // appointmentId only — receptionist's scan does a live lookup, not a data dump
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Scan at reception to check in', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Show this QR code when you arrive', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                          SizedBox(width: 8),
                          Expanded(child: Text('Live queue tracking starts after check-in', style: TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  StreamBuilder<List<HospitalModel>>(
                    stream: ref.read(bookingHospitalRepoProvider).watchHospitals(),
                    builder: (context, snap) {
                      final matches = (snap.data ?? []).where((h) => h.id == appointment.hospitalId);
                      final name = matches.isNotEmpty ? matches.first.name : '—';
                      return _InfoRow(icon: Icons.local_hospital_outlined, label: 'Hospital', value: name);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  StreamBuilder<List<DepartmentModel>>(
                    stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(appointment.hospitalId),
                    builder: (context, snap) {
                      final matches = (snap.data ?? []).where((d) => d.id == appointment.departmentId);
                      final name = matches.isNotEmpty ? matches.first.name : '—';
                      return _InfoRow(icon: Icons.category_outlined, label: 'Department', value: name);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  const _InfoRow(icon: Icons.person_outline, label: 'Doctor', value: 'Assigned when called'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _InfoRow(icon: Icons.calendar_today_outlined, label: 'Date', value: appointment.scheduledDate),
                  if (appointment.scheduledTimeSlot != null) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _InfoRow(icon: Icons.access_time, label: 'Slot', value: appointment.scheduledTimeSlot!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is a booking slot, not a guaranteed time. Your exact queue position is assigned on arrival.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_none),
              label: const Text('Notifications are already on for this visit'),
              onPressed: () => context.push('/patient/notifications'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}