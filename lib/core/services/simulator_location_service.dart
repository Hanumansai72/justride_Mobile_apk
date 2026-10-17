import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/simulated_location_packet.dart';

/// Service responsible for receiving real-time simulated motorcycle GPS
/// telemetry from the JustRide Web Ride Simulator over WebSocket.
class SimulatorLocationService {
  SimulatorLocationService._();
  static final SimulatorLocationService instance = SimulatorLocationService._();

  WebSocketChannel? _socket;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _shouldReconnect = false;
  int _lastTimestamp = 0;

  static const String _defaultHostKey = 'simulator_host';
  String _host = '127.0.0.1:8080';

  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> latencyMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<SimulatedLocationPacket?> latestPacketNotifier =
      ValueNotifier<SimulatedLocationPacket?>(null);

  final StreamController<Position> _positionStreamController =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionStreamController.stream;
  bool get isConnected => isConnectedNotifier.value;
  String get host => _host;

  /// Initializes host preferences and connects if enabled
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _host = prefs.getString(_defaultHostKey) ?? '127.0.0.1:8080';
    } catch (e) {
      debugPrint('[SimLoc] Error reading prefs: $e');
    }
  }

  /// Sets custom simulator host (e.g. 192.168.1.100:8080)
  Future<void> setHost(String newHost) async {
    _host = newHost
        .trim()
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_defaultHostKey, _host);
    } catch (_) {}
    if (isConnected || _shouldReconnect) {
      disconnect();
      connect();
    }
  }

  /// Starts listening to the simulation WebSocket
  Future<bool> connect() async {
    if (_isConnecting || isConnected) return true;
    _shouldReconnect = true;
    _isConnecting = true;

    final candidateHosts = [
      _host,
      '127.0.0.1:8080',
      '10.0.2.2:8080', // Android emulator loopback to host PC
    ];

    for (final h in candidateHosts) {
      final wsUrl =
          h.startsWith('ws://') || h.startsWith('wss://') ? h : 'ws://$h';
      try {
        debugPrint('[SimLoc] Attempting connection to $wsUrl...');
        final socket = WebSocketChannel.connect(Uri.parse(wsUrl));
        try {
          await socket.ready.timeout(const Duration(milliseconds: 1500));
        } catch (_) {
          unawaited(socket.sink.close());
          rethrow;
        }

        _socket = socket;
        _isConnecting = false;
        isConnectedNotifier.value = true;
        _host = h;
        debugPrint('[SimLoc] ✓ Successfully connected to simulator at $wsUrl');

        _listenToSocket();
        return true;
      } catch (e) {
        debugPrint('[SimLoc] Connection to $wsUrl failed: $e');
      }
    }

    _isConnecting = false;
    isConnectedNotifier.value = false;
    _scheduleReconnect();
    return false;
  }

  void _listenToSocket() {
    _socket?.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'SIM_LOCATION') {
            final packet = SimulatedLocationPacket.fromJson(json);

            // Stale or out-of-order packet rejection
            if (packet.timestamp < _lastTimestamp) return;
            _lastTimestamp = packet.timestamp;

            // Latency calculation
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final latency = (nowMs - packet.timestamp).clamp(0, 999);
            latencyMsNotifier.value = latency;

            latestPacketNotifier.value = packet;

            // Convert to Position and broadcast
            final pos = packet.toPosition();
            _positionStreamController.add(pos);
          }
        } catch (e) {
          debugPrint('[SimLoc] Error parsing packet: $e');
        }
      },
      onDone: () {
        debugPrint('[SimLoc] WebSocket connection closed by server');
        isConnectedNotifier.value = false;
        _socket = null;
        if (_shouldReconnect) _scheduleReconnect();
      },
      onError: (err) {
        debugPrint('[SimLoc] WebSocket error: $err');
        isConnectedNotifier.value = false;
        _socket = null;
        if (_shouldReconnect) _scheduleReconnect();
      },
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!_shouldReconnect) return;

    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_shouldReconnect && !isConnected) {
        connect();
      }
    });
  }

  /// Disconnects and stops reconnect attempts
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.sink.close();
    _socket = null;
    isConnectedNotifier.value = false;
  }

  void dispose() {
    disconnect();
    _positionStreamController.close();
  }
}
