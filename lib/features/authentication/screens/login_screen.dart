import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/routes.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/motion.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_inputs.dart';
import '../providers/auth_controller.dart';
import '../widgets/auth_layout.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: ref.read(authRepositoryProvider).rememberedEmail ?? '');
  final _password = TextEditingController();
  bool _remember = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(_email.text, _password.text, remember: _remember);
      // The router redirects automatically once signed in.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillDemo() {
    setState(() {
      _email.text = AppConstants.demoEmail;
      _password.text = AppConstants.demoPassword;
      _error = null;
    });
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text);
    final formKey = GlobalKey<FormState>();
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Reset password'),
            content: SizedBox(
              width: 380,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your account email and we will send password reset instructions.',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: ctx.palette.textMuted),
                    ),
                    const SizedBox(height: Space.md),
                    AppTextField(
                      label: 'Email address',
                      controller: controller,
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      validator: Validators.email,
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            actions: [
              AppSecondaryButton(label: 'Cancel', expand: false, height: 46, onPressed: () => Navigator.pop(ctx, false)),
              AppPrimaryButton(
                label: 'Send link',
                expand: false,
                height: 46,
                loading: busy,
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  setLocal(() => busy = true);
                  await ref.read(authRepositoryProvider).requestPasswordReset(controller.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (sent == true && mounted) {
      showAppSnack(
        context,
        'If an account exists, reset instructions have been sent. (Demo mode: no email is actually sent.)',
        type: SnackType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to continue managing enrollments.',
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
                        child: AppBanner(title: 'Sign-in failed', message: _error!),
                      ),
              ),
              AppTextField(
                fieldKey: const Key('login-email'),
                label: 'Email address',
                hint: 'you@company.com',
                controller: _email,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                validator: Validators.email,
              ),
              const SizedBox(height: Space.md),
              AppPasswordField(
                fieldKey: const Key('login-password'),
                label: 'Password',
                controller: _password,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(
                    child: AppCheckboxTile(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v),
                      child: Text('Remember me', style: t.bodyMedium),
                    ),
                  ),
                  AppLinkButton(label: 'Forgot password?', onPressed: _forgotPassword),
                ],
              ),
              const SizedBox(height: Space.lg),
              AppPrimaryButton(
                key: const Key('login-submit'),
                label: 'Sign in',
                icon: Icons.arrow_forward_rounded,
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: Space.md),
              Container(
                padding: const EdgeInsets.all(Space.md - 2),
                decoration: BoxDecoration(
                  color: p.accentTint.withValues(alpha: 0.6),
                  borderRadius: Radii.mdAll,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, color: AppColors.peach, size: 20),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Demo account\n', style: t.labelMedium),
                          TextSpan(
                            text: '${AppConstants.demoEmail} · ${AppConstants.demoPassword}',
                            style: t.bodySmall,
                          ),
                        ]),
                      ),
                    ),
                    AppLinkButton(label: 'Use', onPressed: _fillDemo),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text("Don't have an account?", style: t.bodyMedium?.copyWith(color: p.textMuted)),
                  AppLinkButton(label: 'Create one', onPressed: () => context.go(Routes.register)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
