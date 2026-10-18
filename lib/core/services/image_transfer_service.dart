// lib/core/services/image_transfer_service.dart
//
// Sends a 153 600-byte RGB565 image to the JustRide ESP32 over BLE.
// Mirrors the architecture of ota_service.dart for consistency.
//
// BLE Image Transfer Service (UUID 0xFF20):
//   0xFF21  Image Control  (write)        : START[0x01]+4-byte-LE-size | FINISH[0x02] | ABORT[0x03]
//   0xFF22  Image Data     (write no-rsp) : [seq_lo][seq_hi] + up to 128 bytes RGB565
//   0xFF23  Image Status   (notify/read)  : [status_code][progress_pct]

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum ImageTransferState { idle, preparing, transferring, success, failed }

class ImageTransferProgress {
  final ImageTransferState state;
  final double progress; // 0.0 to 1.0
  final String statusMessage;
  final String? error;

  const ImageTransferProgress({
    required this.state,
    required this.progress,
    required this.statusMessage,
    this.error,
  });

  static const idle = ImageTransferProgress(
    state: ImageTransferState.idle,
    progress: 0,
    statusMessage: '',
  );
}

class ImageTransferService {
  static const String _kImgServiceUuid = 'ff20';
  static const String _kImgControlUuid = 'ff21';
  static const String _kImgDataUuid = 'ff22';
  static const String _kImgStatusUuid = 'ff23';

  static const int _kCmdStart = 0x01;
  static const int _kCmdFinish = 0x02;
  static const int _kCmdAbort = 0x03;
  static const int _kCmdReset = 0x04;

  static const int kDisplayWidth = 320;
  static const int kDisplayHeight = 240;
  static const int kTotalBytes = kDisplayWidth * kDisplayHeight * 2; // 153 600
  static const int kChunkPayload = 128; // bytes of RGB565 data per packet

  BluetoothCharacteristic? _controlChr;
  BluetoothCharacteristic? _dataChr;
  BluetoothCharacteristic? _statusChr;
  StreamSubscription<List<int>>? _statusSub;

  bool _isTransferring = false;
  final progressNotifier = ValueNotifier<ImageTransferProgress>(
    ImageTransferProgress.idle,
  );

  bool get isTransferring => _isTransferring;

  Future<bool> discoverCharacteristics(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      _controlChr = null;
      _dataChr = null;
      _statusChr = null;

      for (final svc in services) {
        final svcId = svc.uuid.toString().toLowerCase().replaceAll('-', '');
        if (!svcId.contains(_kImgServiceUuid)) continue;

        for (final chr in svc.characteristics) {
          final id = chr.uuid.toString().toLowerCase().replaceAll('-', '');
          if (id.contains(_kImgControlUuid)) _controlChr = chr;
          if (id.contains(_kImgDataUuid)) _dataChr = chr;
          if (id.contains(_kImgStatusUuid)) _statusChr = chr;
        }
        break;
      }

      final found = _controlChr != null && _dataChr != null;
      if (!found) {
        debugPrint(
            '[IMG] Image Transfer GATT Service (0xFF20) characteristics not found on device.');
      }
      return found;
    } catch (e) {
      debugPrint('[IMG] Error discovering image characteristics: $e');
      return false;
    }
  }

  Future<bool> sendImage({
    required BluetoothDevice device,
    required Uint8List rgb565Bytes,
  }) async {
    if (_isTransferring) return false;
    if (rgb565Bytes.length != kTotalBytes) {
      debugPrint(
          '[IMG] sendImage: expected $kTotalBytes bytes, got ${rgb565Bytes.length}');
      return false;
    }

    _isTransferring = true;
    _updateProgress(
        ImageTransferState.preparing, 0, 'Connecting to display...');

    try {
      final ok = await discoverCharacteristics(device);
      if (!ok) {
        throw Exception(
            'Image Transfer BLE Service (0xFF20) not found on connected JustRide unit.');
      }

      try {
        await device.requestMtu(256);
      } catch (e) {
        debugPrint('[IMG] MTU negotiation note: $e');
      }

      if (_statusChr != null) {
        try {
          await _statusChr!.setNotifyValue(true);
          _statusSub?.cancel();
          _statusSub = _statusChr!.onValueReceived.listen((data) {
            if (data.length >= 2) {
              debugPrint(
                  '[IMG] ESP32 status: 0x${data[0].toRadixString(16)} ${data[1]}%');
            }
          });
        } catch (e) {
          debugPrint('[IMG] Status notification warning: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 150));

      // 1. Send START command [0x01, size_b0, size_b1, size_b2, size_b3]
      final startPayload = Uint8List(5);
      startPayload[0] = _kCmdStart;
      final bd = ByteData.sublistView(startPayload, 1, 5);
      bd.setUint32(0, kTotalBytes, Endian.little);

      debugPrint('[IMG] Sending START (size=$kTotalBytes bytes)...');
      try {
        await _controlChr!.write(startPayload, withoutResponse: false);
      } catch (_) {
        await _controlChr!.write(startPayload, withoutResponse: true);
      }

      await Future.delayed(const Duration(milliseconds: 250));

      // 2. Send RGB565 data chunks
      final totalChunks = (kTotalBytes / kChunkPayload).ceil();
      _updateProgress(
          ImageTransferState.transferring, 0, 'Sending image (0%)...');

      for (int i = 0; i < totalChunks; i++) {
        if (!_isTransferring) throw Exception('Transfer cancelled.');

        final start = i * kChunkPayload;
        final end = (start + kChunkPayload > kTotalBytes)
            ? kTotalBytes
            : start + kChunkPayload;
        final payload = rgb565Bytes.sublist(start, end);

        final packet = Uint8List(2 + payload.length);
        packet[0] = i & 0xFF;
        packet[1] = (i >> 8) & 0xFF;
        packet.setRange(2, packet.length, payload);

        bool written = false;
        for (int retry = 0; retry < 3 && !written; retry++) {
          try {
            await _dataChr!.write(packet, withoutResponse: false);
            written = true;
          } catch (_) {
            if (retry < 2) {
              await Future.delayed(Duration(milliseconds: 30 * (retry + 1)));
            } else {
              // Try writeWithoutResponse if with-response fails repeatedly
              try {
                await _dataChr!.write(packet, withoutResponse: true);
                written = true;
              } catch (finalErr) {
                throw Exception('Failed to write packet $i: $finalErr');
              }
            }
          }
        }

        final progress = (i + 1) / totalChunks;
        final pct = (progress * 100).toInt();
        if (i % 25 == 0 || i == totalChunks - 1) {
          _updateProgress(ImageTransferState.transferring, progress,
              'Sending image ($pct%)...');
        }
      }

      // 3. Send FINISH command
      debugPrint('[IMG] Sending FINISH...');
      try {
        await _controlChr!.write([_kCmdFinish], withoutResponse: false);
      } catch (_) {
        await _controlChr!.write([_kCmdFinish], withoutResponse: true);
      }

      if (_statusChr == null || !_statusChr!.properties.read) {
        throw Exception('Device cannot confirm image verification.');
      }
      final status = await _statusChr!.read();
      if (status.length < 2 || status[0] != 0x12 || status[1] != 100) {
        throw Exception('Device did not confirm a complete image.');
      }

      _updateProgress(
        ImageTransferState.success,
        1.0,
        'Image sent! Swipe right on device to view.',
      );
      _isTransferring = false;
      return true;
    } catch (e) {
      debugPrint('[IMG] Transfer error: $e');
      _updateProgress(ImageTransferState.failed, 0, 'Transfer failed',
          error: e.toString());
      _isTransferring = false;
      try {
        await _controlChr?.write([_kCmdAbort], withoutResponse: true);
      } catch (_) {}
      return false;
    } finally {
      _statusSub?.cancel();
      _statusSub = null;
    }
  }

  void cancelTransfer() {
    _isTransferring = false;
    _controlChr?.write([_kCmdAbort], withoutResponse: true);
    _updateProgress(ImageTransferState.idle, 0, 'Transfer cancelled.');
  }

  /// Sends a clear / reset image command to restore default display screen
  Future<bool> resetImage(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? ctrl;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase().contains(_kImgServiceUuid)) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase().contains(_kImgControlUuid)) {
              ctrl = c;
              break;
            }
          }
        }
      }
      if (ctrl != null) {
        await ctrl.write([_kCmdReset], withoutResponse: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[ImageTransferService] resetImage error: $e');
      return false;
    }
  }

  void _updateProgress(
    ImageTransferState state,
    double progress,
    String msg, {
    String? error,
  }) {
    progressNotifier.value = ImageTransferProgress(
      state: state,
      progress: progress,
      statusMessage: msg,
      error: error,
    );
  }

  void dispose() {
    _statusSub?.cancel();
    progressNotifier.dispose();
  }
}
