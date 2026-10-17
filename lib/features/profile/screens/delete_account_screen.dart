import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/device_unlink_dialog.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _backend = BackendService.instance;
  Map<String, dynamic>? _status;
  bool _loading = true, _busy = false, _sent = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _otp.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await _backend.getAccountDeletionStatus();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = result.success ? result.data : null;
      _error = result.success ? null : result.message;
    });
  }

  Future<bool> _ensureUnlinked() async {
    final result = await _backend.getAccountDeletionStatus();
    if (!mounted) return false;
    if (!result.success || result.data == null) {
      setState(() => _error = result.message);
      return false;
    }
    setState(() => _status = result.data);
    final linked = result.data!['linkedDevice'];
    if (linked == null) return true;
    final unlinked = await showDeviceUnlinkDialog(context,
        deviceId: linked['_id'].toString(),
        deviceName: linked['devicename']?.toString() ?? 'JustRide device');
    if (!unlinked || !mounted) return false;
    final refreshed = await _backend.getAccountDeletionStatus();
    if (!mounted) return false;
    setState(() => _status = refreshed.data);
    if (!refreshed.success || refreshed.data?['linkedDevice'] != null) {
      setState(() =>
          _error = 'A device is still linked. Unlink it before continuing.');
      return false;
    }
    return true;
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _ensureUnlinked() || !mounted) return;
      if (_status?['requiresPassword'] == true && _password.text.isEmpty) {
        setState(() => _error = 'Enter your current password.');
        return;
      }
      final result =
          await _backend.requestAccountDeletionOtp(password: _password.text);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.message);
        return;
      }
      setState(() {
        _sent = true;
        _otp.clear();
        _cooldown = 60;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _cooldown <= 1) timer.cancel();
        if (mounted) setState(() => _cooldown = (_cooldown - 1).clamp(0, 60));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_otp.text.length != 6) {
      setState(() => _error = 'Enter the six-digit deletion code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _ensureUnlinked() || !mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Delete account permanently?'),
                content: const Text(
                    'Your profile and ride data will be removed. You cannot create another account with this email or phone number.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Delete permanently')),
                ],
              ));
      if (confirmed != true || !mounted) return;
      final result = await _backend.deleteAccount(
          password: _password.text, otp: _otp.text);
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      } else {
        setState(() => _error = result.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Delete account')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Icon(Icons.delete_forever_outlined,
                        color: AppColors.errorText, size: 44),
                    const SizedBox(height: 20),
                    Text('Before you delete your account',
                        style: AppTextStyles.headingMedium),
                    const SizedBox(height: 12),
                    Text(
                        '1. Unlink your device so it is released for another account.\n2. Verify the deletion code sent to your registered email.\n3. Confirm permanent deletion.',
                        style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppColors.errorSurface,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text(
                          'Your profile, rides, saved places and support records will be removed. Your email and phone number stay reserved and cannot be used to create a new account.'),
                    ),
                    const SizedBox(height: 20),
                    if (_status?['linkedDevice'] != null) ...[
                      const Text(
                          'A device is linked. You will be asked to unlink it before a deletion code can be sent.'),
                      const SizedBox(height: 16),
                    ],
                    if (_status?['requiresPassword'] == true) ...[
                      TextField(
                          controller: _password,
                          obscureText: true,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                              labelText: 'Current password')),
                      const SizedBox(height: 16),
                    ],
                    if (_status != null)
                      Text(
                          'Deletion code will be sent to ${_status!['email']}.',
                          style: AppTextStyles.bodySmall),
                    const SizedBox(height: 16),
                    if (_sent) ...[
                      TextField(
                          controller: _otp,
                          enabled: !_busy,
                          maxLength: 6,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                              labelText: 'Account deletion OTP')),
                      const Text(
                          'This code expires in 10 minutes. The device unlink code cannot be used here.'),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(_error!,
                              style:
                                  const TextStyle(color: AppColors.errorText))),
                    if (_busy)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator())),
                    OutlinedButton(
                        onPressed: _busy || _status == null || _cooldown > 0
                            ? null
                            : _sendCode,
                        child: Text(_cooldown > 0
                            ? 'Resend in ${_cooldown}s'
                            : (_sent
                                ? 'Resend deletion code'
                                : 'Send deletion code'))),
                    if (_status == null)
                      TextButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('Try again')),
                    if (_sent)
                      FilledButton(
                          onPressed: _busy ? null : _delete,
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.errorText,
                              foregroundColor: AppColors.background),
                          child: const Text('Delete account')),
                    TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel')),
                  ],
                ),
        ),
      );
}
