import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

class DateTimeConfirmScreen extends ConsumerStatefulWidget {
  const DateTimeConfirmScreen({
    super.key,
    required this.hospitalId,
    required this.hospitalName,
    required this.departmentId,
    required this.departmentName,
  });

  final String hospitalId;
  final String hospitalName;
  final String departmentId;
  final String departmentName;

  @override
  ConsumerState<DateTimeConfirmScreen> createState() => _DateTimeConfirmScreenState();
}

class _DateTimeConfirmScreenState extends ConsumerState<DateTimeConfirmScreen> {
  DateTime _date = DateTime.now();
  String? _selectedSlot;
  bool _confirming = false;

  /// Slot start has already begun (or passed) for the selected calendar day.
  bool _isSlotPast(String slot) {
    final startPart = slot.split('-').first.trim();
    final parts = startPart.split(':');
    if (parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    final slotStart = DateTime(_date.year, _date.month, _date.day, hour, minute);
    return !slotStart.isAfter(DateTime.now());
  }

  /// Green = quiet, orange = filling up, red = crowded / full.
  Color _crowdColor({required int remaining, required int capacity}) {
    if (capacity <= 0 || remaining <= 0) return AppColors.critical;
    final fill = 1.0 - (remaining / capacity);
    if (fill >= 0.7) return AppColors.critical;
    if (fill >= 0.4) return AppColors.urgent;
    return AppColors.secondary;
  }

  String _crowdLabel({required int remaining, required int capacity}) {
    if (capacity <= 0 || remaining <= 0) return 'Full';
    final fill = 1.0 - (remaining / capacity);
    if (fill >= 0.7) return 'Busy';
    if (fill >= 0.4) return 'Moderate';
    return 'Quiet';
  }

  @override
  Widget build(BuildContext context) {
    final bookingState = ref.watch(bookingControllerProvider);
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);

    return Scaffold(
      appBar: AppBar(title: const Text('Date & Time')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR SELECTION', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(widget.departmentName, style: Theme.of(context).textTheme.titleMedium),
                    Text(widget.hospitalName, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "This is a booking slot — your exact queue position is assigned when you check in. A doctor is assigned in real time when you're called, not in advance.",
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Date', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined, color: AppColors.primary),
                title: Text(DateFormat('EEEE, MMM d, yyyy').format(_date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setState(() {
                      _date = picked;
                      _selectedSlot = null;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Time Slot', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const _CrowdLegend(),
            const SizedBox(height: 12),
            FutureBuilder<List<({String slot, int remaining, int capacity})>>(
              key: ValueKey(dateStr),
              future: ref.read(appointmentRepositoryProvider).getAvailableSlots(
                hospitalId: widget.hospitalId,
                departmentId: widget.departmentId,
                date: dateStr,
              ),
              builder: (context, snap) {
                if (snap.hasError) return Text('Error loading slots: ${snap.error}');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final slots = snap.data!;
                if (slots.isEmpty) return const Text('No slots configured for this date');
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: slots.map((s) {
                    final past = _isSlotPast(s.slot);
                    final full = s.remaining <= 0;
                    final disabled = past || full;
                    final selected = _selectedSlot == s.slot;
                    final crowd = _crowdColor(remaining: s.remaining, capacity: s.capacity);
                    final label = past
                        ? '${s.slot} · Past'
                        : full
                            ? '${s.slot} · Full'
                            : '${s.slot} · ${_crowdLabel(remaining: s.remaining, capacity: s.capacity)}';

                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: disabled ? null : (_) => setState(() => _selectedSlot = s.slot),
                      selectedColor: crowd.withValues(alpha: 0.25),
                      backgroundColor: disabled
                          ? AppColors.surfaceVariant.withValues(alpha: 0.45)
                          : crowd.withValues(alpha: 0.12),
                      disabledColor: AppColors.surfaceVariant.withValues(alpha: 0.4),
                      side: BorderSide(
                        color: disabled ? AppColors.textSecondary.withValues(alpha: 0.25) : crowd.withValues(alpha: 0.7),
                      ),
                      labelStyle: TextStyle(
                        color: disabled
                            ? AppColors.textSecondary.withValues(alpha: 0.45)
                            : (selected ? crowd : AppColors.textPrimary),
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Booking Summary', style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                  const Divider(height: 1),
                  _SummaryRow(icon: Icons.local_hospital_outlined, label: 'Hospital', value: widget.hospitalName),
                  _SummaryRow(icon: Icons.category_outlined, label: 'Department', value: widget.departmentName),
                  const _SummaryRow(icon: Icons.person_outline, label: 'Doctor', value: 'Assigned when called'),
                  _SummaryRow(icon: Icons.calendar_today_outlined, label: 'Date', value: DateFormat('EEEE, d MMM yyyy').format(_date)),
                  _SummaryRow(icon: Icons.access_time, label: 'Slot', value: _selectedSlot ?? '—', isLast: true),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: (bookingState.isLoading || _confirming)
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm Booking'),
              onPressed: (_selectedSlot == null || bookingState.isLoading || _confirming)
                  ? null
                  : () async {
                setState(() => _confirming = true);

                final result = await ref.read(bookingControllerProvider.notifier).book(
                  hospitalId: widget.hospitalId,
                  departmentId: widget.departmentId,
                  scheduledDate: dateStr,
                  scheduledTimeSlot: _selectedSlot,
                );

                if (result == null) {
                  if (mounted) {
                    setState(() => _confirming = false);
                    final error = ref.read(bookingControllerProvider).error;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error?.toString() ?? 'Booking failed')));
                  }
                  return;
                }

                // Fetch the real, server-populated appointment back
                // rather than hand-constructing one — this is what
                // guarantees patientName/patientPhoneNumber shown on
                // the QR screen match what's actually in the database.
                final appointment = await ref.read(appointmentRepositoryProvider).fetchAppointmentById(result.appointmentId);

                if (!mounted) return;
                setState(() => _confirming = false);

                if (appointment == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Booked, but could not load confirmation details.')),
                  );
                  context.go('/patient/home');
                  return;
                }

                context.pushReplacement('/patient/appointment-qr', extra: appointment);
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'You can reschedule up to 2 hours before your slot',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrowdLegend extends StatelessWidget {
  const _CrowdLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: const [
        _LegendDot(color: AppColors.secondary, label: 'Quiet'),
        _LegendDot(color: AppColors.urgent, label: 'Moderate'),
        _LegendDot(color: AppColors.critical, label: 'Busy / Full'),
        _LegendDot(color: AppColors.textSecondary, label: 'Past (unavailable)'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label, required this.value, this.isLast = false});
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}
