import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/services/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/motion.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_cards.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_layout.dart';
import '../../../environments/presentation/providers/environment_providers.dart';
import '../../../connectivity/app_features_provider.dart';
import '../../../connectivity/connectivity_service.dart';
import '../../../connectivity/connectivity_widgets.dart';
import '../../../environments/presentation/widgets/environment_widgets.dart';
import '../../domain/employee_photo.dart';
import '../../domain/employee_registration.dart';
import '../providers/registration_controller.dart';
import '../widgets/photo_picker_panel.dart';

/// Registers an employee with `POST /api/employee/add`. The form maps 1:1
/// to the backend's `EmployeeForm`: name, dateOfBirth, designation, photo.
class RegisterEmployeeScreen extends ConsumerStatefulWidget {
  const RegisterEmployeeScreen({super.key});

  @override
  ConsumerState<RegisterEmployeeScreen> createState() => _RegisterEmployeeScreenState();
}

class _RegisterEmployeeScreenState extends ConsumerState<RegisterEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _designation = TextEditingController();
  DateTime? _dob;
  EmployeePhoto? _photo;
  bool _attempted = false;

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(registrationControllerProvider.notifier);
    if (ref.read(registrationControllerProvider).submitting) return;
    controller.clearError();
    setState(() => _attempted = true);
    final fieldsOk = _formKey.currentState?.validate() ?? false;
    if (!fieldsOk || _photo == null) {
      showAppSnack(context, 'Please complete the highlighted fields.', type: SnackType.warning);
      return;
    }
    FocusScope.of(context).unfocus();
    final outcome = await controller.submit(
      EmployeeRegistration(name: _name.text, dateOfBirth: _dob!, designation: _designation.text, photo: _photo!),
    );
    if (!mounted || outcome == null) return;
    context.go(Routes.enrollSuccess, extra: outcome);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationControllerProvider);
    final env = ref.watch(activeEnvironmentProvider);
    final features = ref.watch(appFeaturesProvider);
    final preferFront = ref.watch(settingsProvider.select((s) => s.preferFrontCamera));
    final busy = state.submitting;
    final now = DateTime.now();
    final t = Theme.of(context).textTheme;

    // Where the registration goes. Client builds never show server URLs.
    final upload = ref.watch(connectionStatusProvider.select((s) => s.shouldAttemptServer));
    final target = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm + 2),
      child: Row(
        children: [
          Icon(
            upload ? Icons.cloud_upload_outlined : Icons.smartphone_rounded,
            color: upload ? environmentColor(env) : AppColors.info,
            size: 22,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: const Key('registration-target'),
                  upload
                      ? (features.environmentIndicator ? 'Saving to ${env.environmentName}' : 'Saving to the server')
                      : 'Saving on this device',
                  style: t.labelLarge,
                ),
                Text(
                  upload
                      ? (features.environmentIndicator ? env.baseUrl ?? '' : 'A copy is also kept on this device')
                      : 'You\'re offline. The employee will be uploaded when the server is available.',
                  style: t.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const ConnectivityPill(compact: true),
        ],
      ),
    );

    final photo = PhotoPickerPanel(
      photo: _photo,
      enabled: !busy,
      preferFrontCamera: preferFront,
      errorText: _attempted && _photo == null ? 'Add a photograph of the employee.' : null,
      onChanged: (p) => setState(() => _photo = p),
    );

    final fields = AppCard(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Employee details', style: t.titleMedium),
            const SizedBox(height: 4),
            Text('All fields are required.', style: t.bodySmall),
            const SizedBox(height: Space.lg - 4),
            AppTextField(
              fieldKey: const Key('field-name'),
              label: 'Full name',
              hint: 'e.g. Amina Rahman',
              controller: _name,
              icon: Icons.person_outline_rounded,
              enabled: !busy,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: EmployeeValidators.name,
            ),
            const SizedBox(height: Space.md),
            AppDateField(
              key: const Key('field-dob'),
              label: 'Date of birth',
              value: _dob,
              firstDate: DateTime(now.year - 100),
              lastDate: now,
              initialDate: DateTime(now.year - 30, now.month, 1),
              validator: (d) => EmployeeValidators.dateOfBirth(d),
              onChanged: (d) => setState(() => _dob = d),
            ),
            const SizedBox(height: Space.md),
            AppTextField(
              fieldKey: const Key('field-designation'),
              label: 'Designation',
              hint: 'e.g. Software Engineer',
              controller: _designation,
              icon: Icons.work_outline_rounded,
              enabled: !busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              validator: EmployeeValidators.designation,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    );

    final progress = state.progress;
    final submit = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: context.motion(Motion.fast),
          child: state.error == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(state.error),
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: AppBanner(title: 'The server rejected this registration', message: state.error!),
                ),
        ),
        AppPrimaryButton(
          key: const Key('register-submit'),
          label: 'Register employee',
          icon: Icons.how_to_reg_rounded,
          loading: busy,
          onPressed: busy ? null : _submit,
        ),
        if (busy) ...[
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(value: progress == null || progress >= 1 ? null : progress, minHeight: 4),
          ),
          const SizedBox(height: 6),
          Text(
            progress == null || progress >= 1
                ? 'Registering and generating face template…'
                : 'Uploading photo… ${(progress * 100).round()}%',
            textAlign: TextAlign.center,
            style: t.bodySmall,
          ),
        ],
      ],
    );

    final header = AppPageHeader(
      title: 'Register employee',
      subtitle: 'Capture or upload a photo and enter the employee\'s details.',
      leading: context.isMobile
          ? AppIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: busy ? null : () => context.go(Routes.home),
            )
          : null,
    );

    final wide = context.screenWidth >= 980;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            autovalidateMode: _attempted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: AppPage(
              maxWidth: 1180,
              bottomPadding: context.useSidebar ? Space.xl : Space.xxl,
              children: [
                header,
                target,
                const SizedBox(height: Space.lg),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: photo),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            fields,
                            const SizedBox(height: Space.lg),
                            submit,
                            const SizedBox(height: Space.md),
                            const _PrivacyNote(),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  photo,
                  const SizedBox(height: Space.lg),
                  fields,
                  const SizedBox(height: Space.lg),
                  submit,
                  const SizedBox(height: Space.md),
                  const _PrivacyNote(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: context.palette.textMuted),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(
            'The photo is sent to the server, which generates the face template and adds the employee to the '
            'recognition watch list. A copy is kept on this device so no registration is lost while offline.',
            style: t.bodySmall,
          ),
        ),
      ],
    );
  }
}
