import 'notification_listener_service.dart';
import 'navigation_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ble_navigation_service.dart';

/// Call state representing active phone telephony
enum PhoneCallStatus {
  idle,
  ringing,
  offhook, // In call / call answered
}

/// Information model for incoming/active call
class IncomingCallInfo {
  final PhoneCallStatus status;
  final String callerNumber;
  final String callerName;

  const IncomingCallInfo({
    this.status = PhoneCallStatus.idle,
    this.callerNumber = '',
    this.callerName = '',
  });

  bool get isRinging => status == PhoneCallStatus.ringing;
  bool get isOffhook => status == PhoneCallStatus.offhook;
  bool get hasActiveCall => isRinging || isOffhook;

  String get displayName {
    if (callerName.isNotEmpty) return callerName;
    if (callerNumber.isNotEmpty) return callerNumber;
    return 'Incoming Call';
  }

  IncomingCallInfo copyWith({
    PhoneCallStatus? status,
    String? callerNumber,
    String? callerName,
  }) {
    return IncomingCallInfo(
      status: status ?? this.status,
      callerNumber: callerNumber ?? this.callerNumber,
      callerName: callerName ?? this.callerName,
    );
  }
}

/// Service managing native incoming call detection, answering, and rejection.
class TelephonyService {
  TelephonyService._();
  static final TelephonyService instance = TelephonyService._();

  static const MethodChannel _channel =
      MethodChannel('com.justride.app/telephony');

  final ValueNotifier<IncomingCallInfo> callInfoNotifier =
      ValueNotifier<IncomingCallInfo>(const IncomingCallInfo());

  bool _isListening = false;
  bool _watchingRideState = false;
  bool _callWasSuppressed = false;

  void init() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
    startListening();
    if (!_watchingRideState) {
      _watchingRideState = true;
      NavigationService.instance.rideStateNotifier
          .addListener(_onRideStateChange);
    }
  }

  Future<void> startListening() async {
    if (_isListening) return;
    try {
      await _channel.invokeMethod('startListening');
      _isListening = true;
    } catch (e) {
      _isListening = false;
    }
  }

  Future<void> stopListening() async {
    try {
      _isListening = false;
      await _channel.invokeMethod('stopListening');
    } catch (e) {}
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onCallStateChanged') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final stateStr = args?['state'] as String? ?? 'IDLE';
      final number = args?['number'] as String? ?? '';

      PhoneCallStatus newStatus;
      switch (stateStr) {
        case 'RINGING':
          newStatus = PhoneCallStatus.ringing;
          break;
        case 'OFFHOOK':
          newStatus = PhoneCallStatus.offhook;
          break;
        case 'IDLE':
        default:
          newStatus = PhoneCallStatus.idle;
          break;
      }

      callInfoNotifier.value = IncomingCallInfo(
        status: newStatus,
        callerNumber: number,
        callerName: args?['name'] as String? ?? '',
      );

      await syncDisplay();
    } else if (call.method == 'onCallPermissionChanged') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final granted = args?['granted'] == true;
      _isListening = granted;
    }
  }

  void _onRideStateChange() {
    final suppressed = !NotificationListenerService.instance.allowCallOverlay;
    if (_callWasSuppressed == suppressed) return;
    _callWasSuppressed = suppressed;
    if (callInfoNotifier.value.hasActiveCall) unawaited(syncDisplay());
  }

  Future<void> syncDisplay() async {
    final notifications = NotificationListenerService.instance;
    await notifications.settingsReady;
    int actions = 0;
    try {
      actions = await _channel.invokeMethod<int>('getCallCapabilities') ?? 0;
    } catch (_) {}
    final info = notifications.allowCallOverlay
        ? callInfoNotifier.value
        : const IncomingCallInfo();
    await BleNavigationService.instance.sendCallState(
        info.status.index, actions, info.displayName,
        number: info.callerNumber);
  }

  Future<bool> answerCall() async {
    if (!callInfoNotifier.value.isRinging) return false;
    try {
      return await _channel.invokeMethod<bool>('answerCall') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rejectCall() async {
    if (!callInfoNotifier.value.hasActiveCall) return false;
    try {
      return await _channel.invokeMethod<bool>('rejectCall') ?? false;
    } catch (e) {
      return false;
    }
  }
}
