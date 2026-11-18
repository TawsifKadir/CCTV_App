import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_features.dart';
import '../../../core/services/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_inputs.dart';
import '../../connectivity/app_features_provider.dart';
import '../../environments/presentation/providers/environment_providers.dart';
import '../providers/auth_controller.dart';
import '../widgets/auth_layout.dart';
import '../widgets/dev_login_tools.dart';

/// Sign-in against `POST /api/auth/login` on the active environment.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(text: ref.read(authRepositoryProvider).rememberedUsername ?? '');
  final _password = TextEditingController();
  bool _remember = true;
  bool _loading = false;
  String? _error;
  late final String? _notice = ref.read(authControllerProvider.notifier).takeSignOutReason();

  @override
  void dispose() {
    _username.dispose();
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
      await ref.read(authControllerProvider.notifier).login(_username.text, _password.text, remember: _remember);
      // The router redirects to the dashboard once signed in.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _demo(String username, String password) {
    try {
      ref.read(authControllerProvider.notifier).loginDemo(username, password);
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // Compile-time constant first: in production builds the developer
    // widgets (and the credential strings) are removed by the compiler.
    final devTools = !kProductionBuild && ref.watch(appFeaturesProvider).adminMode;
    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to continue managing enrollments.',
      footer: devTools
          ? const DevEnvironmentPicker()
          : (ref.watch(activeEnvironmentProvider).isSecure ? null : const _InsecureConnectionNote()),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                // Never zero: AnimatedSize with a zero duration re-lays itself out
                // during layout (a framework assertion) when reduced motion is on.
                duration: context.reduceMotion ? const Duration(milliseconds: 1) : Motion.medium,
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: AppBanner(key: const Key('login-error'), title: 'Sign-in failed', message: _error!),
                      )
                    : _notice != null
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: AppBanner(type: SnackType.info, message: _notice),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              AppTextField(
                fieldKey: const Key('login-username'),
                label: 'Username',
                hint: 'Your username',
                controller: _username,
                icon: Icons.person_outline_rounded,
                enabled: !_loading,
                autofillHints: const [AutofillHints.username],
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
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
              AppCheckboxTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v),
                child: Text('Remember me on this device', style: t.bodyMedium),
              ),
              const SizedBox(height: Space.lg),
              AppPrimaryButton(
                key: const Key('login-submit'),
                label: 'Sign in',
                icon: Icons.arrow_forward_rounded,
                loading: _loading,
                onPressed: _submit,
              ),
              if (devTools) ...[const SizedBox(height: Space.md), DemoLoginCard(busy: _loading, onContinue: _demo)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the server is reached over plain HTTP (production must move to
/// HTTPS before handling real employee data).
class _InsecureConnectionNote extends StatelessWidget {
  const _InsecureConnectionNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md),
    child: AppBanner(
      key: const Key('insecure-connection'),
      type: SnackType.warning,
      message: 'This connection to the server is not encrypted (HTTP). Ask your administrator to enable HTTPS.',
    ),
  );
}
