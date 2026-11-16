import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_inputs.dart';
import '../../../data/remote/api_contracts.dart';
import '../providers/auth_controller.dart';
import '../widgets/auth_layout.dart';

/// Operator (staff) account registration. Employees are registered separately.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _org = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _terms = false;
  bool _termsError = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _org, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    setState(() => _termsError = !_terms);
    if (!valid || !_terms) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).register(RegisterRequest(
            fullName: _name.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
            organization: _org.text,
          ));
      if (mounted) {
        showAppSnack(context, 'Welcome to Enrolly, ${_name.text.trim().split(' ').first}!', type: SnackType.success);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showTerms() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms & privacy (demo)'),
        content: const SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Text(
              'Operator sign-in in this build is a local demo.\n\n'
              '• Operator accounts are stored only on this device, with passwords hashed (never in plain text).\n'
              '• Employee details and photographs are sent to the selected backend environment, which creates '
              'the face template. They are not stored on this device.\n'
              '• Inform employees and obtain any consent your organisation requires before capturing a photograph.',
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    final twoCol = context.screenWidth >= 1200;

    Widget pair(Widget a, Widget b) => twoCol
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: a),
            const SizedBox(width: Space.md),
            Expanded(child: b),
          ])
        : Column(children: [a, const SizedBox(height: Space.md), b]);

    return AuthLayout(
      title: 'Create operator account',
      subtitle: 'Operators register employees and manage their records.',
      leading: AppIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Back to sign in',
        onPressed: () => context.go(Routes.login),
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: context.motion(Motion.medium),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: AppBanner(title: 'Could not create account', message: _error!),
                      ),
              ),
              AppTextField(
                label: 'Full name',
                hint: 'e.g. Jordan Blake',
                controller: _name,
                icon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: Validators.fullName,
              ),
              const SizedBox(height: Space.md),
              pair(
                AppTextField(
                  label: 'Email address',
                  hint: 'you@company.com',
                  controller: _email,
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                ),
                AppTextField(
                  label: 'Phone number',
                  hint: '+1 555 010 0000',
                  controller: _phone,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: Validators.phone,
                ),
              ),
              const SizedBox(height: Space.md),
              AppTextField(
                label: 'Organization',
                hint: 'Branch or company name',
                optional: true,
                controller: _org,
                icon: Icons.apartment_outlined,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: Space.md),
              pair(
                AppPasswordField(
                  label: 'Password',
                  controller: _password,
                  hint: 'At least 8 characters',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.password,
                ),
                AppPasswordField(
                  label: 'Confirm password',
                  controller: _confirm,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => Validators.confirmPassword(v, _password.text),
                ),
              ),
              const SizedBox(height: Space.xs),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Use 8+ characters with upper & lower case letters and a number.',
                  style: t.bodySmall,
                ),
              ),
              const SizedBox(height: Space.md),
              AppCheckboxTile(
                value: _terms,
                errorText: _termsError ? 'Please accept the terms to continue' : null,
                onChanged: (v) => setState(() {
                  _terms = v;
                  if (v) _termsError = false;
                }),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('I agree to the ', style: t.bodyMedium),
                    GestureDetector(
                      onTap: _showTerms,
                      child: Text(
                        'terms & privacy policy',
                        style: t.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              AppPrimaryButton(
                label: 'Create account',
                icon: Icons.check_rounded,
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: Space.md),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Already registered?', style: t.bodyMedium?.copyWith(color: p.textMuted)),
                  AppLinkButton(label: 'Sign in', onPressed: () => context.go(Routes.login)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
