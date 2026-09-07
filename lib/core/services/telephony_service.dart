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

  void init() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
    startListening();
  }

  Future<void> startListening() async {
    if (_isListening) return;
    try {
      await _channel.invokeMethod('startListening');
      _isListening = true;
      debugPrint('[TelephonyService] Started telephony monitoring');
    } catch (e) {
      _isListening = false;
      debugPrint('[TelephonyService] startListening error: $e');
    }
  }

  Future<void> stopListening() async {
    try {
      _isListening = false;
      await _channel.invokeMethod('stopListening');
    } catch (e) {
      debugPrint('[TelephonyService] stopListening error: $e');
    }
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onCallStateChanged') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final stateStr = args?['state'] as String? ?? 'IDLE';
      final number = args?['number'] as String? ?? '';

      debugPrint('[TelephonyService] onCallStateChanged: $stateStr ($number)');

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
        callerName: number.isNotEmpty ? 'Caller: $number' : 'Incoming Call',
      );

      if (newStatus == PhoneCallStatus.ringing) {
        // Cellular calls are also shown on the HUD, even if the system call
        // notification itself is suppressed by the phone manufacturer.
        await BleNavigationService.instance.sendLatestNotification(
          'Incoming call',
          number.isEmpty ? 'Phone call' : number,
        );
      }
    } else if (call.method == 'onCallPermissionChanged') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final granted = args?['granted'] == true;
      _isListening = granted;
      debugPrint('[TelephonyService] Phone-state permission granted: $granted');
    }
  }

  /// Accepts / answers the ringing call
  Future<bool> answerCall() async {
    try {
      debugPrint('[TelephonyService] Answering incoming call...');
      final bool success = await _channel.invokeMethod('answerCall') ?? false;
      if (success) {
        callInfoNotifier.value = callInfoNotifier.value.copyWith(
          status: PhoneCallStatus.offhook,
        );
      }
      return success;
    } catch (e) {
      debugPrint('[TelephonyService] answerCall error: $e');
      return false;
    }
  }

  /// Rejects / hangs up the ringing or active call
  Future<bool> rejectCall() async {
    try {
      debugPrint('[TelephonyService] Rejecting call...');
      final bool success = await _channel.invokeMethod('rejectCall') ?? false;
      // Only reset UI to idle if the native rejection actually succeeded
      if (success) {
        callInfoNotifier.value =
            const IncomingCallInfo(status: PhoneCallStatus.idle);
      }
      return success;
    } catch (e) {
      debugPrint('[TelephonyService] rejectCall error: $e');
      // Reset state on exception — call state is indeterminate after an error
      callInfoNotifier.value =
          const IncomingCallInfo(status: PhoneCallStatus.idle);
      return false;
    }
  }

  /// Test helper for simulating an incoming call in debug/demo
  void simulateIncomingCall(
      {String number = '+91 98765 43210', String name = 'John Rider'}) {
    callInfoNotifier.value = IncomingCallInfo(
      status: PhoneCallStatus.ringing,
      callerNumber: number,
      callerName: name,
    );
  }

  /// Test helper for dismissing a simulated call
  void simulateEndCall() {
    callInfoNotifier.value =
        const IncomingCallInfo(status: PhoneCallStatus.idle);
  }
}
