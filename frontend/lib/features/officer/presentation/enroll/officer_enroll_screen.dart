import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/step_progress_indicator.dart';
import '../../../citizen/complaints/data/department_catalog.dart';
import '../../application/enrollment_controller.dart';
import '../../application/officer_session_controller.dart';
import '../../data/officer_models.dart';
import '../../data/officer_repository.dart';
import 'jurisdiction_cascade.dart';

/// The 5-step officer enrollment stepper.
class OfficerEnrollScreen extends ConsumerStatefulWidget {
  const OfficerEnrollScreen({super.key});

  @override
  ConsumerState<OfficerEnrollScreen> createState() =>
      _OfficerEnrollScreenState();
}

class _OfficerEnrollScreenState extends ConsumerState<OfficerEnrollScreen> {
  static const _stepLabels = [
    'Department',
    'Designation',
    'Jurisdiction',
    'Details',
    'Review',
  ];

  int _step = 0;
  bool _submitting = false;

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _employeeId;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(officerEnrollmentProvider);
    _name = TextEditingController(text: draft.fullName);
    _phone = TextEditingController(text: draft.phoneNumber);
    _employeeId = TextEditingController(text: draft.employeeId);
    _email = TextEditingController(text: draft.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _employeeId.dispose();
    _email.dispose();
    super.dispose();
  }

  OfficerEnrollmentController get _controller =>
      ref.read(officerEnrollmentProvider.notifier);

  bool _canAdvance(OfficerEnrollmentDraft draft) {
    switch (_step) {
      case 0:
        return draft.hasDepartment;
      case 1:
        return draft.hasDesignation;
      case 2:
        return draft.hasBoundary;
      case 3:
        return _name.text.trim().isNotEmpty && _phone.text.length == 10;
      default:
        return true;
    }
  }

  void _next() {
    if (_step == 3) {
      _controller.setDetails(
        fullName: _name.text.trim(),
        phoneNumber: _phone.text,
        employeeId: _employeeId.text.trim(),
        email: _email.text.trim(),
      );
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      context.pop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _submit() async {
    final draft = ref.read(officerEnrollmentProvider);
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ref.read(officerRepositoryProvider).enroll(
            fullName: draft.fullName,
            phoneNumber: draft.phoneNumber,
            departmentId: draft.departmentId!,
            designationId: draft.designation!.designationId,
            boundaryId: draft.boundaryId!,
            employeeId: draft.employeeId.isEmpty ? null : draft.employeeId,
            email: draft.email.isEmpty ? null : draft.email,
          );
      _controller.reset();
      await ref.read(officerSessionProvider.notifier).signIn(
            token: result.sessionToken,
            fullName: result.fullName,
            officerId: result.officerId,
            status: result.status,
          );
      // Router redirects to officer home.
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        _showPositionTakenDialog(e.message);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showPositionTakenDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.block, color: Theme.of(context).colorScheme.error),
        title: const Text('Position unavailable'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(officerEnrollmentProvider);
    final isReview = _step == _stepLabels.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Officer Enrollment'),
        leading: BackButton(onPressed: _back),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: StepProgressIndicator(
                    currentStep: _step + 1,
                    totalSteps: _stepLabels.length,
                    label: _stepLabels[_step],
                  ),
                ),
                Expanded(child: _buildStep(draft)),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: _step == 0 ? 'Cancel' : 'Back',
                          onPressed: _submitting ? null : _back,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: PrimaryButton(
                          label: isReview ? 'Submit' : 'Next',
                          icon: isReview ? Icons.check : Icons.arrow_forward,
                          isLoading: _submitting,
                          onPressed: _canAdvance(draft)
                              ? (isReview ? _submit : _next)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(OfficerEnrollmentDraft draft) {
    switch (_step) {
      case 0:
        return _DepartmentStep(
          selectedId: draft.departmentId,
          onSelect: _controller.setDepartment,
        );
      case 1:
        return _DesignationStep(
          departmentId: draft.departmentId!,
          selectedId: draft.designation?.designationId,
          onSelect: _controller.setDesignation,
        );
      case 2:
        return _JurisdictionStep(draft: draft, onSelected: _controller.setBoundary);
      case 3:
        return _DetailsStep(
          name: _name,
          phone: _phone,
          employeeId: _employeeId,
          email: _email,
          onChanged: () => setState(() {}),
        );
      default:
        return _ReviewStep(draft: draft);
    }
  }
}

// --- Step 1: Department ------------------------------------------------------

class _DepartmentStep extends StatelessWidget {
  const _DepartmentStep({required this.selectedId, required this.onSelect});

  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      children: [
        for (final dept in kDepartments)
          _SelectableTile(
            icon: dept.icon,
            label: dept.label,
            selected: dept.id == selectedId,
            onTap: () => onSelect(dept.id),
          ),
      ],
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected ? scheme.onPrimaryContainer : scheme.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Step 2: Designation -----------------------------------------------------

class _DesignationStep extends ConsumerWidget {
  const _DesignationStep({
    required this.departmentId,
    required this.selectedId,
    required this.onSelect,
  });

  final String departmentId;
  final int? selectedId;
  final ValueChanged<DesignationOption> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officerDesignationsProvider(departmentId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(e is ApiException ? e.message : 'Couldn’t load roles.'),
      ),
      data: (items) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final d = items[i];
          final selected = d.designationId == selectedId;
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: selected ? scheme.primaryContainer : scheme.surface,
            borderRadius: AppRadius.mdAll,
            child: InkWell(
              borderRadius: AppRadius.mdAll,
              onTap: () => onSelect(d),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.designationName,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('Operates at ${d.levelName} level',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: scheme.primary),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Step 3: Jurisdiction ----------------------------------------------------

class _JurisdictionStep extends ConsumerWidget {
  const _JurisdictionStep({required this.draft, required this.onSelected});

  final OfficerEnrollmentDraft draft;
  final void Function(int, String) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officerBoundaryLevelsProvider(draft.departmentId!));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(e is ApiException ? e.message : 'Couldn’t load areas.'),
      ),
      data: (levels) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Select the exact area you’re responsible for.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          JurisdictionCascade(
            key: ValueKey(
              '${draft.departmentId}-${draft.designation!.designationId}',
            ),
            departmentId: draft.departmentId!,
            designation: draft.designation!,
            levels: levels,
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

// --- Step 4: Details ---------------------------------------------------------

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.name,
    required this.phone,
    required this.employeeId,
    required this.email,
    required this.onChanged,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController employeeId;
  final TextEditingController email;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _Field(
          controller: name,
          label: 'Full name',
          hint: 'e.g. R. Kumar',
          icon: Icons.person_outline,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Phone number', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: phone,
          keyboardType: TextInputType.number,
          maxLength: 10,
          onChanged: (_) => onChanged(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: const InputDecoration(
            counterText: '',
            hintText: '98765 43210',
            prefixIcon: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Icon(Icons.phone_outlined, size: 20),
            ),
            prefixText: '+91 ',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Field(
          controller: employeeId,
          label: 'Employee ID (optional)',
          hint: 'e.g. GCC-12345',
          icon: Icons.badge_outlined,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Field(
          controller: email,
          label: 'Email (optional)',
          hint: 'you@department.gov.in',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final VoidCallback onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
          ),
        ),
      ],
    );
  }
}

// --- Step 5: Review ----------------------------------------------------------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.draft});

  final OfficerEnrollmentDraft draft;

  @override
  Widget build(BuildContext context) {
    final dept = kDepartments
        .where((d) => d.id == draft.departmentId)
        .cast<DepartmentOption?>()
        .firstWhere((d) => true, orElse: () => null);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _row(context, 'Department', dept?.label ?? draft.departmentId ?? '—'),
        _row(context, 'Designation', draft.designation?.designationName ?? '—'),
        _row(context, 'Jurisdiction', draft.boundaryName ?? '—'),
        _row(context, 'Name', draft.fullName),
        _row(context, 'Phone', '+91 ${draft.phoneNumber}'),
        if (draft.employeeId.isNotEmpty)
          _row(context, 'Employee ID', draft.employeeId),
        if (draft.email.isNotEmpty) _row(context, 'Email', draft.email),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'You’ll be enrolled with status “Pending verification” until your '
          'department confirms your account.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
