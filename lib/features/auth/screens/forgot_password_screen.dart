import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/utils/user_facing_error.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false, _sent = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await BackendService.instance.forgotPassword(_email.text.trim());
      if (!mounted) return;
      setState(() {
        if (result.success)
          _sent = true;
        else
          _error = userFacingError(result.message,
              fallback: 'The reset email couldn’t be sent. Please try again.');
      });
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'The reset email couldn’t be sent. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                          _sent
                              ? Icons.mark_email_read_outlined
                              : Icons.lock_reset_rounded,
                          size: 40,
                          color: AppColors.primary),
                      const SizedBox(height: 24),
                      Text(_sent ? 'Check your email' : 'Recover your account',
                          style: AppTextStyles.displayMedium),
                      const SizedBox(height: 12),
                      Text(
                          _sent
                              ? 'If an account uses this email, a password reset link will arrive shortly.'
                              : 'Enter your account email to request a password reset link.',
                          style: AppTextStyles.bodyLarge),
                      const SizedBox(height: 28),
                      if (!_sent) ...[
                        TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                                labelText: 'Email address'),
                            validator: (value) =>
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(value?.trim() ?? '')
                                    ? null
                                    : 'Enter a valid email address.'),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.errorLight)))
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                            onPressed: _busy ? null : _send,
                            child: Text(
                                _busy ? 'Sending link…' : 'Send reset link')),
                      ] else
                        FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pushNamedAndRemoveUntil(
                                    '/login', (_) => false),
                            child: const Text('Back to sign in')),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                  .pushNamed('/reset-password'),
                          child: const Text('Use a reset link')),
                    ]))),
      );
}
