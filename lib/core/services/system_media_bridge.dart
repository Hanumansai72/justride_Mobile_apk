import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _mediaChannel = MethodChannel('com.justride.app/system_media');
const _companionChannel = MethodChannel('com.justride.app/companion');
const _mediaTimeout = Duration(seconds: 3);

Future<bool> _repairMediaBridge() async {
  try {
    return await _companionChannel
            .invokeMethod<bool>('repairMediaBridge')
            .timeout(_mediaTimeout) ==
        true;
  } on Exception catch (error) {
    debugPrint('[BleMedia] Bridge repair failed: ${error.runtimeType}');
    return false;
  }
}

/// A rejected command must not hide a readable player snapshot.
Future<Map<Object?, Object?>> readSystemMedia({int? command}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const {'state': 0};
  }
  if (command == 7) await _repairMediaBridge();
  if (command != null && command != 7) {
    try {
      if (command == 8) {
        await const MethodChannel('com.justride.app/system_notifications')
            .invokeMethod('openNotificationSettings')
            .timeout(_mediaTimeout);
      } else if (command >= 1 && command <= 6) {
        const methods = [
          'play',
          'pause',
          'next',
          'previous',
          'volumeUp',
          'volumeDown'
        ];
        final accepted = await _mediaChannel
            .invokeMethod<bool>(methods[command - 1])
            .timeout(_mediaTimeout);
        if (accepted != true) {
          debugPrint('[BleMedia] Command $command rejected by player');
        }
      }
    } on Exception catch (error) {
      debugPrint('[BleMedia] Command $command failed: ${error.runtimeType}');
    }
  }
  Future<Map<Object?, Object?>> snapshot() async {
    final value = await _mediaChannel
        .invokeMapMethod<Object?, Object?>('getMediaSnapshot')
        .timeout(_mediaTimeout);
    return value != null && value['state'] is num ? value : const {'state': 7};
  }

  try {
    return await snapshot();
  } on MissingPluginException {
    if (await _repairMediaBridge()) {
      try {
        return await snapshot();
      } on Exception catch (error) {
        debugPrint(
            '[BleMedia] Snapshot after repair failed: ${error.runtimeType}');
      }
    }
  } on PlatformException catch (error) {
    debugPrint('[BleMedia] Snapshot failed: ${error.code}');
  } on TimeoutException {
    debugPrint('[BleMedia] Snapshot timed out');
  }
  return const {'state': 7};
}
