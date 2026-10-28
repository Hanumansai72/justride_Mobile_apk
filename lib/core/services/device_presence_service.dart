import 'dart:async';
import '../network/api_client.dart';

/// Only called after a packet actually arrives from the connected device.
class DevicePresenceService {
  DevicePresenceService._();
  static final instance = DevicePresenceService._();
  DateTime? _lastAttempt;
  String? _lastIdentity;
  bool _sending = false;

  void report(String address) {
    final api = ApiClient.instance;
    if (!api.isAuthenticated || _sending) return;
    final identity = '${api.token}:$address';
    final now = DateTime.now();
    if (_lastIdentity == identity &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(minutes: 1)) return;
    _lastIdentity = identity;
    _lastAttempt = now;
    _sending = true;
    unawaited(api
        .post<void>('/devices/heartbeat', body: {'BLE_ADDRESS': address})
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _sending = false));
  }
}
