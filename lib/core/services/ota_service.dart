import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

enum OtaState {
  idle,
  downloading,
  preparing,
  transferring,
  verifying,
  success,
  failed,
}

class OtaProgress {
  final OtaState state;
  final double progress; // 0.0 to 1.0
  final String statusMessage;
  final String? error;

  const OtaProgress({
    required this.state,
    required this.progress,
    required this.statusMessage,
    this.error,
  });

  static const initial = OtaProgress(
    state: OtaState.idle,
    progress: 0.0,
    statusMessage: 'Ready',
  );
}

/// Dedicated OTA Service for JustRide Wireless Firmware Updates
class JustRideOtaService {
  JustRideOtaService._();
  static final JustRideOtaService instance = JustRideOtaService._();

  // UUIDs matching firmware ble.c
  static const String _kOtaServiceUuid = 'ff10';
  static const String _kOtaControlUuid = 'ff11';
  static const String _kOtaDataUuid = 'ff12';
  static const String _kOtaStatusUuid = 'ff13';

  // OTA Control OpCodes
  static const int _kCmdStart = 0x01;
  static const int _kCmdFinish = 0x02;
  static const int _kCmdAbort = 0x03;
  static const int _kCmdReboot = 0x04;

  final ValueNotifier<OtaProgress> progressNotifier =
      ValueNotifier<OtaProgress>(OtaProgress.initial);

  BluetoothCharacteristic? _controlChr;
  BluetoothCharacteristic? _dataChr;
  BluetoothCharacteristic? _statusChr;
  StreamSubscription<List<int>>? _statusSub;
  bool _isUpdating = false;

  bool get isUpdating => _isUpdating;

  /// Discover OTA GATT characteristics
  Future<bool> _discoverOtaCharacteristics(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      _controlChr = null;
      _dataChr = null;
      _statusChr = null;

      for (final svc in services) {
        final sUuid = svc.uuid.toString().toLowerCase().replaceAll('-', '');
        if (sUuid.contains(_kOtaServiceUuid)) {
          for (final chr in svc.characteristics) {
            final cUuid = chr.uuid.toString().toLowerCase().replaceAll('-', '');
            if (cUuid.contains(_kOtaControlUuid)) _controlChr = chr;
            if (cUuid.contains(_kOtaDataUuid)) _dataChr = chr;
            if (cUuid.contains(_kOtaStatusUuid)) _statusChr = chr;
          }
        }
      }

      final found =
          _controlChr != null && _dataChr != null && _statusChr != null;
      if (!found) {
        debugPrint(
            '[OTA] Error: JustRide OTA GATT Service (0xFF10) not found on device.');
      }
      return found;
    } catch (e) {
      debugPrint('[OTA] Error discovering characteristics: $e');
      return false;
    }
  }

  /// Download firmware from backend CDN & flash to device
  Future<bool> downloadAndFlashFirmware({
    required BluetoothDevice device,
    required String downloadUrl,
    required String deviceId,
    required String targetVersion,
  }) async {
    if (_isUpdating) return false;
    _isUpdating = true;

    try {
      // Step 1: Download firmware binary over HTTPS
      _updateProgress(OtaState.downloading, 0.05,
          'Downloading firmware v$targetVersion...');
      debugPrint('[OTA] Fetching firmware binary from: $downloadUrl');

      Uint8List firmwareBytes;
      if (downloadUrl.startsWith('http')) {
        final response = await http.get(Uri.parse(downloadUrl));
        if (response.statusCode != 200) {
          throw Exception(
              'Failed to download firmware binary (HTTP ${response.statusCode})');
        }
        firmwareBytes = response.bodyBytes;
      } else {
        throw Exception('A valid firmware download URL is required.');
      }

      debugPrint(
          '[OTA] Download complete: ${firmwareBytes.length} bytes. Initiating BLE flash...');

      // Step 2: Flash to ESP32 over BLE
      final success =
          await _flashRawBytes(device: device, firmwareBytes: firmwareBytes);
      return success;
    } catch (e) {
      debugPrint('[OTA] Download and flash failed: $e');
      _updateProgress(OtaState.failed, 0.0, 'Update failed',
          error:
              'Unable to update your device. Keep it connected and try again.');
      _isUpdating = false;
      return false;
    }
  }

  /// Direct binary flasher
  Future<bool> flashFirmware({
    required BluetoothDevice device,
    required Uint8List firmwareBytes,
  }) async {
    if (_isUpdating) return false;
    _isUpdating = true;
    return await _flashRawBytes(device: device, firmwareBytes: firmwareBytes);
  }

  Future<bool> _flashRawBytes({
    required BluetoothDevice device,
    required Uint8List firmwareBytes,
  }) async {
    _updateProgress(OtaState.preparing, 0.0, 'Preparing JustRide device...');

    try {
      if (firmwareBytes.length < 24 || firmwareBytes[0] != 0xE9) {
        throw Exception('Invalid ESP32 firmware image.');
      }

      // 1. Discover OTA GATT Services & Characteristics
      final ok = await _discoverOtaCharacteristics(device);
      if (!ok) {
        throw Exception('OTA GATT service not found on device.');
      }

      // 2. Negotiate higher MTU for fast, safe OTA chunking (up to 256 or 512 bytes)
      int negotiatedMtu = 247;
      try {
        negotiatedMtu = await device.requestMtu(256);
        debugPrint('[OTA] Negotiated MTU: $negotiatedMtu bytes');
      } catch (e) {
        debugPrint('[OTA] MTU negotiation optional note: $e');
      }

      // 3. Subscribe before START so the final device verification cannot be missed.
      final finalStatus = Completer<int>();
      int? deviceFailure;
      bool updateStarted = false;
      bool finishSent = false;
      await _statusChr!.setNotifyValue(true);
      await _statusSub?.cancel();
      _statusSub = _statusChr!.onValueReceived.listen((data) {
        if (data.isNotEmpty) {
          final statusCode = data[0];
          final progressPct = data.length > 1 ? data[1] : 0;
          debugPrint(
              '[OTA] Notification from ESP32 -> Status: $statusCode, Pct: $progressPct%');

          if (!updateStarted) return;
          if ((statusCode == 4 && finishSent) ||
              (statusCode >= 5 && statusCode <= 8)) {
            if (statusCode != 4) deviceFailure = statusCode;
            if (!finalStatus.isCompleted) finalStatus.complete(statusCode);
          }
        }
      });

      await Future.delayed(const Duration(milliseconds: 200));

      final size = firmwareBytes.length;
      final startPayload = Uint8List(5);
      startPayload[0] = _kCmdStart;
      final byteData = ByteData.sublistView(startPayload, 1, 5);
      byteData.setUint32(0, size, Endian.little);

      debugPrint('[OTA] Sending START command (Size: $size bytes)...');
      updateStarted = true;
      await _controlChr!.write(startPayload, withoutResponse: false);

      await Future.delayed(const Duration(milliseconds: 400));

      // Calculate safe chunk size based on MTU (header takes 3 bytes in ATT + 2 bytes sequence)
      // Keep chunks at safe 128 bytes for reliable GATT Write With Response across all Android versions
      const chunkSize = 128;
      final totalChunks = (size / chunkSize).ceil();
      _updateProgress(OtaState.transferring, 0.0, 'Installing update (0%)...');

      // Flow-controlled chunk loop:
      // withoutResponse=false (Write With Response) ensures the Android GATT stack
      // waits for the ESP32 ATT_WRITE_RSP before the next packet is sent.
      // This is the ONLY reliable fix for ERROR_GATT_WRITE_REQUEST_BUSY (201).
      for (int i = 0; i < totalChunks; i++) {
        if (!_isUpdating) {
          throw Exception('OTA update cancelled.');
        }
        if (deviceFailure != null) {
          throw Exception(
              'Device rejected firmware update (status $deviceFailure).');
        }

        final start = i * chunkSize;
        final end = (start + chunkSize > size) ? size : start + chunkSize;
        final chunkData = firmwareBytes.sublist(start, end);

        // [seq_lo, seq_hi, ...data]
        final packet = Uint8List(2 + chunkData.length);
        packet[0] = i & 0xFF;
        packet[1] = (i >> 8) & 0xFF;
        packet.setRange(2, packet.length, chunkData);

        // Write WITH response – waits for ESP32 ATT acknowledgement before
        // proceeding. Eliminates ERROR_GATT_WRITE_REQUEST_BUSY entirely.
        bool written = false;
        for (int retry = 0; retry < 4 && !written; retry++) {
          try {
            await _dataChr!.write(packet, withoutResponse: false);
            written = true;
          } catch (err) {
            debugPrint(
                '[OTA] Chunk $i write failed (attempt ${retry + 1}/4): $err');
            if (retry < 3) {
              await Future.delayed(Duration(milliseconds: 50 * (retry + 1)));
            } else {
              rethrow;
            }
          }
        }

        final progress = (i + 1) / totalChunks;
        final pct = (progress * 100).toInt();
        if (i % 10 == 0 || i == totalChunks - 1) {
          debugPrint('[OTA] Chunk $i/$totalChunks written. Progress: $pct%');
        }
        _updateProgress(
            OtaState.transferring, progress, 'Installing update ($pct%)...');
      }

      _updateProgress(OtaState.verifying, 0.98, 'Verifying update...');
      debugPrint('[OTA] Sending FINISH command...');
      finishSent = true;
      await _controlChr!.write([_kCmdFinish], withoutResponse: false);
      final result = await finalStatus.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
            'Device did not confirm firmware verification.'),
      );
      if (result != 4) {
        throw Exception('Device rejected firmware update (status $result).');
      }

      _updateProgress(
          OtaState.success, 1.0, 'Update successful! Restarting device...');
      debugPrint('[OTA] Sending REBOOT command...');
      try {
        await _controlChr!.write([_kCmdReboot], withoutResponse: true);
      } catch (e) {
        debugPrint('[OTA] Firmware verified, but reboot command failed: $e');
        _updateProgress(OtaState.success, 1.0,
            'Update verified. Restart the device to apply it.');
      }

      _isUpdating = false;
      return true;
    } catch (e) {
      debugPrint('[OTA] Flash error: $e');
      _updateProgress(OtaState.failed, 0.0, 'Update failed',
          error:
              'Unable to update your device. Keep it connected and try again.');
      _isUpdating = false;
      try {
        await _controlChr?.write([_kCmdAbort], withoutResponse: true);
      } catch (_) {}
      return false;
    } finally {
      _statusSub?.cancel();
    }
  }

  void cancelUpdate() {
    _isUpdating = false;
    _controlChr?.write([_kCmdAbort], withoutResponse: true);
    _updateProgress(OtaState.idle, 0.0, 'Update cancelled.');
  }

  void _updateProgress(OtaState state, double progress, String msg,
      {String? error}) {
    progressNotifier.value = OtaProgress(
      state: state,
      progress: progress,
      statusMessage: msg,
      error: error,
    );
  }
}
