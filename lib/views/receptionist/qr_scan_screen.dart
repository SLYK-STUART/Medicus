import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import 'checkin_screen.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  bool _processing = false;

  Future<void> _handleScan(String appointmentId) async {
    if (_processing) return;

    setState(() => _processing = true);

    try {
      final appointment = await ref
          .read(appointmentRepositoryProvider)
          .fetchAppointmentById(appointmentId);

      if (appointment == null) {
        _showResult('Appointment not found', isError: true);
        return;
      }

      if (appointment.status != 'booked') {
        _showResult(
          'This appointment is already "${appointment.status}" — cannot check in again.',
          isError: true,
        );
        return;
      }

      await ref.read(queueRepositoryProvider).checkIn(
        patientName: appointment.patientName,
        patientPhoneNumber: appointment.patientPhoneNumber,
        appointmentId: appointment.id,
        patientId: appointment.patientId,
        doctorId: appointment.doctorId,
        tokenNumber: appointment.tokenNumber,
        hospitalId: appointment.hospitalId,
        date: appointment.scheduledDate,
        departmentId: appointment.departmentId,
      );

      _showResult(
        'Checked in — token #${appointment.tokenNumber}',
        isError: false,
      );
    } catch (e) {
      _showResult('Failed: $e', isError: true);
    }
  }

  void _showResult(String message, {required bool isError}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.secondary,
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _processing = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scannerHeight = math.min(
              380.0,
              math.max(220.0, constraints.maxHeight * 0.40),
            );

            final scannerWidth = math.min(constraints.maxWidth, 420.0);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title moved into body
                    Text(
                      "Patient Check-In",
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      "Scan Patient QR Code",
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      "Position the patient's QR code inside the frame below to check them into the queue.",
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey.shade700),
                    ),

                    const SizedBox(height: 24),

                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                              width: scannerWidth,
                              height: scannerHeight,
                              child: MobileScanner(
                                onDetect: (capture) {
                                  if (_processing) return;

                                  final value =
                                      capture.barcodes.firstOrNull?.rawValue;

                                  if (value != null) {
                                    _handleScan(value);
                                  }
                                },
                              ),
                            ),
                          ),

                          IgnorePointer(
                            child: Container(
                              width: math.min(scannerWidth * .70, 250),
                              height: math.min(scannerWidth * .70, 250),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: AppColors.secondary,
                                  width: 4,
                                ),
                              ),
                            ),
                          ),

                          if (_processing)
                            Container(
                              width: scannerWidth,
                              height: scannerHeight,
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Card(
                      elevation: 0,
                      color: AppColors.secondary.withOpacity(.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.qr_code_scanner),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Ensure the QR code is fully visible and well-lit. The patient will automatically be checked in once a valid QR code is detected.",
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    FilledButton.icon(
                      onPressed:
                      _processing ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text("Back"),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
