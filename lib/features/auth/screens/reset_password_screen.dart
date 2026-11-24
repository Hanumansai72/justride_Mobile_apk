import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/utils/user_facing_error.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _link = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false, _obscure = true, _loaded = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      final arguments = ModalRoute.of(context)?.settings.arguments;
      if (arguments is Map && arguments['token'] is String)
        _link.text = arguments['token'] as String;
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _resetCode() {
    final text = _link.text.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http'))
      return uri.queryParameters['token'] ??
          (uri.pathSegments.isNotEmpty &&
                  uri.pathSegments.contains('reset-password')
              ? uri.pathSegments.last
              : '');
    return text;
  }

  Future<void> _reset() async {
    if (_busy || !_form.currentState!.validate()) return;
    final token = _resetCode();
    if (token.isEmpty) {
      setState(
          () => _error = 'This reset link is incomplete. Request a new one.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await BackendService.instance
          .resetPassword(token: token, newPassword: _password.text);
      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Password updated. Sign in with your new password.')));
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      } else {
        setState(() => _error = userFacingError(result.message,
            fallback:
                'Your password couldn’t be reset. Request a new link and try again.'));
      }
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Your password couldn’t be reset. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Set a new password')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Choose your new password',
                          style: AppTextStyles.displayMedium),
                      const SizedBox(height: 12),
                      Text(
                          'Use the reset link from your email to update your password.',
                          style: AppTextStyles.bodyLarge),
                      const SizedBox(height: 28),
                      TextFormField(
                          controller: _link,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                              labelText: 'Reset link or code',
                              hintText: 'Paste from your email'),
                          validator: (value) => value?.trim().isNotEmpty == true
                              ? null
                              : 'Enter the reset link from your email.'),
                      const SizedBox(height: 20),
                      TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                              labelText: 'New password',
                              suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(_obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined))),
                          validator: (value) => (value?.length ?? 0) >= 6
                              ? null
                              : 'Use at least 6 characters.'),
                      const SizedBox(height: 20),
                      TextFormField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                              labelText: 'Confirm new password'),
                          validator: (value) => value == _password.text &&
                                  value?.isNotEmpty == true
                              ? null
                              : 'Passwords do not match.'),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.errorLight)))
                      ],
                      const SizedBox(height: 28),
                      FilledButton(
                          onPressed: _busy ? null : _reset,
                          child: Text(_busy
                              ? 'Updating password…'
                              : 'Update password')),
                    ]))),
      );
}
