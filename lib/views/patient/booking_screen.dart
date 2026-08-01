import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/department_model.dart';
import '../../models/hospital_model.dart';
import '../../viewmodels/patient/booking_viewmodel.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, this.initialHospitalId, this.initialDepartmentId});
  final String? initialHospitalId;
  final String? initialDepartmentId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String? _hospitalId;
  String? _hospitalName;
  String? _departmentId;
  String? _departmentName;

  @override
  Widget build(BuildContext context) {
    final canContinue = _hospitalId != null && _departmentId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Book Appointment')),
      body: SafeArea(
        child: Column(
          children: [
            _StepHeader(hospitalDone: _hospitalId != null, departmentDone: _departmentId != null),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  const _SectionLabel(step: 1, label: 'Choose a Hospital'),
                  const SizedBox(height: 12),
                  StreamBuilder<List<HospitalModel>>(
                    stream: ref.read(bookingHospitalRepoProvider).watchHospitals(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                      final hospitals = snap.data!;
                      if (hospitals.isEmpty) return const Text('No hospitals available yet');

                      // Quick-rebook pre-fill: only hospitalId/departmentId are
                      // passed by the home screen's shortcut (no names) — once
                      // the stream resolves a match, fill in the name and
                      // select it, same as if the user had tapped it.
                      if (_hospitalId == null && widget.initialHospitalId != null) {
                        final match = hospitals.where((h) => h.id == widget.initialHospitalId);
                        if (match.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _hospitalId = match.first.id;
                                _hospitalName = match.first.name;
                              });
                            }
                          });
                        }
                      }

                      return Column(
                        children: hospitals.map((h) {
                          final selected = h.id == _hospitalId;
                          return _SelectableCard(
                            selected: selected,
                            leadingIcon: Icons.local_hospital_outlined,
                            title: h.name,
                            subtitle: h.address,
                            onTap: () => setState(() {
                              _hospitalId = h.id;
                              _hospitalName = h.name;
                              _departmentId = null;
                              _departmentName = null;
                            }),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  if (_hospitalId != null) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel(step: 2, label: 'Choose a Department'),
                    const SizedBox(height: 12),
                    StreamBuilder<List<DepartmentModel>>(
                      stream: ref.read(bookingDepartmentRepoProvider).watchDepartments(_hospitalId!),
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                        final depts = snap.data!;
                        if (depts.isEmpty) return const Text('No departments set up for this hospital yet');

                        if (_departmentId == null &&
                            widget.initialDepartmentId != null &&
                            _hospitalId == widget.initialHospitalId) {
                          final match = depts.where((d) => d.id == widget.initialDepartmentId);
                          if (match.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _departmentId = match.first.id;
                                  _departmentName = match.first.name;
                                });
                              }
                            });
                          }
                        }

                        return GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.3,
                          children: depts.map((d) {
                            final selected = d.id == _departmentId;
                            return _SelectableCard(
                              selected: selected,
                              leadingIcon: Icons.category_outlined,
                              title: d.name,
                              subtitle: null,
                              dense: true,
                              onTap: () => setState(() {
                                _departmentId = d.id;
                                _departmentName = d.name;
                              }),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: FilledButton(
                onPressed: canContinue
                    ? () => context.push('/patient/book/date-time', extra: {
                  'hospitalId': _hospitalId!,
                  'hospitalName': _hospitalName!,
                  'departmentId': _departmentId!,
                  'departmentName': _departmentName!,
                })
                    : null,
                child: const Text('Continue to Date & Time'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.hospitalDone, required this.departmentDone});
  final bool hospitalDone;
  final bool departmentDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          _StepDot(done: hospitalDone, active: true, label: 'Hospital'),
          _StepLine(done: hospitalDone),
          _StepDot(done: departmentDone, active: hospitalDone, label: 'Department'),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.done, required this.active, required this.label});
  final bool done;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: done ? AppColors.primary : (active ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant),
          child: done ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: done || active ? AppColors.primary : AppColors.textSecondary)),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        height: 2,
        color: done ? AppColors.primary : AppColors.surfaceVariant,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.step, required this.label});
  final int step;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(radius: 12, backgroundColor: AppColors.primary, child: Text('$step', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.selected,
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dense = false,
  });
  final bool selected;
  final IconData leadingIcon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: dense ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: dense
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(leadingIcon, color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.primary : null)),
              if (selected) ...[
                const SizedBox(height: 4),
                const Text('Selected', style: TextStyle(color: AppColors.primary, fontSize: 12)),
              ],
            ],
          )
              : Row(
            children: [
              CircleAvatar(backgroundColor: AppColors.surfaceVariant, child: Icon(leadingIcon, color: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppColors.primary : null)),
                    if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle : Icons.chevron_right, color: selected ? AppColors.primary : AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}