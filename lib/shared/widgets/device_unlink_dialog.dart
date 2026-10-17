import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/backend_service.dart';

Future<bool> showDeviceUnlinkDialog(
  BuildContext context, {
  required String deviceId,
  required String deviceName,
}) async =>
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _DeviceUnlinkDialog(deviceId: deviceId, deviceName: deviceName)) ??
    false;

class _DeviceUnlinkDialog extends StatefulWidget {
  const _DeviceUnlinkDialog({required this.deviceId, required this.deviceName});
  final String deviceId;
  final String deviceName;
  @override
  State<_DeviceUnlinkDialog> createState() => _DeviceUnlinkDialogState();
}

class _DeviceUnlinkDialogState extends State<_DeviceUnlinkDialog> {
  final _code = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await BackendService.instance.requestDeviceUnlinkOtp(widget.deviceId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = result.success;
      _error = result.success ? null : result.message;
    });
    if (result.success) {
      _cooldown = 60;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _cooldown <= 1) timer.cancel();
        if (mounted) setState(() => _cooldown = (_cooldown - 1).clamp(0, 60));
      });
    }
  }

  Future<void> _unlink() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter the six-digit unlink code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await BackendService.instance
        .unlinkDeviceWithOtp(widget.deviceId, _code.text);
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Unlink device first'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                '${widget.deviceName} is linked to your account. Unlinking releases it for another account. Account deletion is blocked until this is complete.'),
            const SizedBox(height: 16),
            if (_sent) ...[
              const Text(
                  'Enter the unlink code sent to your registered email. It expires in 10 minutes.'),
              const SizedBox(height: 12),
              TextField(
                  controller: _code,
                  enabled: !_busy,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Unlink OTP')),
            ],
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator()),
          ])),
          actions: [
            TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            if (!_sent)
              FilledButton(
                  onPressed: _busy ? null : _send,
                  child: const Text('Send unlink code')),
            if (_sent) ...[
              TextButton(
                  onPressed: _busy || _cooldown > 0 ? null : _send,
                  child: Text(_cooldown > 0
                      ? 'Resend in ${_cooldown}s'
                      : 'Resend code')),
              FilledButton(
                  onPressed: _busy ? null : _unlink,
                  child: const Text('Unlink device')),
            ],
          ],
        ),
      );
}
