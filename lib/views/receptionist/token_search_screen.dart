import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../viewmodels/auth/auth_viewmodel.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';
import 'checkin_screen.dart'; // queueRepositoryProvider

class TokenSearchScreen extends ConsumerStatefulWidget {
  const TokenSearchScreen({super.key});
  @override
  ConsumerState<TokenSearchScreen> createState() => _TokenSearchScreenState();
}

class _TokenSearchScreenState extends ConsumerState<TokenSearchScreen> {
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final hospitalId = profile?.hospitalId;
    if (hospitalId == null) return const Scaffold(body: Center(child: Text('No hospitalId on profile')));

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Find Patient')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Token number or patient name',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<AppointmentModel>>(
                  stream: ref.read(appointmentRepositoryProvider).watchTodaysAppointmentsForHospital(hospitalId: hospitalId, date: today),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                    final query = _searchController.text.trim().toLowerCase();
                    final results = query.isEmpty
                        ? <AppointmentModel>[]
                        : snap.data!.where((a) {
                      final tokenMatch = a.tokenNumber.toString().startsWith(query);
                      final nameMatch = a.patientName.toLowerCase().contains(query);
                      return tokenMatch || nameMatch;
                    }).toList();

                    if (query.isEmpty) {
                      return const Center(child: Text('Enter a token number or patient name to search'));
                    }
                    if (results.isEmpty) {
                      return const Center(child: Text('No matching patient found today'));
                    }

                    return ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final a = results[i];
                        final color = statusColor(a.status);
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Text('#${a.tokenNumber}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            title: Text(a.patientName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${a.departmentId} · ${a.status}'),
                            trailing: a.status == 'booked'
                                ? FilledButton(
                              onPressed: () async {
                                try {
                                  await ref.read(queueRepositoryProvider).checkIn(
                                    patientName: a.patientName,
                                    patientPhoneNumber: a.patientPhoneNumber,
                                    appointmentId: a.id,
                                    patientId: a.patientId,
                                    doctorId: a.doctorId,
                                    tokenNumber: a.tokenNumber,
                                    hospitalId: a.hospitalId,
                                    date: a.scheduledDate,
                                    departmentId: a.departmentId,
                                  );
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked in')));
                                } catch (e) {
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                                }
                              },
                              child: const Text('Check In'),
                            )
                                : null,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}