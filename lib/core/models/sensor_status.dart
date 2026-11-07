/// Live MPU telemetry on FF32. Roll/pitch are signed tenths of a degree.
class SensorStatus {
  final int state, motion;
  final double roll, pitch;
  final DateTime receivedAt;
  final double? yaw, turnRate;
  final bool gyroAvailable, gyroFresh;
  const SensorStatus(
      {required this.state,
      required this.motion,
      required this.roll,
      required this.pitch,
      required this.receivedAt,
      this.yaw,
      this.turnRate,
      this.gyroAvailable = false,
      this.gyroFresh = false});

  String get label => const [
        'Sensor not detected',
        'Calibration needed',
        'Calibrating — keep still',
        'Ready',
        'Sensor read error',
        'Waiting for stillness — automatic retry'
      ][state];
  String get movement =>
      const ['Level', 'Forward', 'Backward', 'Left', 'Right'][motion];
  bool get isReady => state == 3;

  static SensorStatus? parse(List<int> bytes) {
    final v2 = bytes.length == 13 && bytes[1] == 2;
    if ((!v2 && (bytes.length != 8 || bytes[1] != 1)) ||
        bytes[0] != 0x1a ||
        bytes[2] > 5 ||
        bytes[3] > 4 ||
        bytes.any((v) => v < 0 || v > 255)) {
      return null;
    }
    int signed(int offset) {
      final n = bytes[offset] | (bytes[offset + 1] << 8);
      return n >= 32768 ? n - 65536 : n;
    }

    final roll = signed(4) / 10, pitch = signed(6) / 10;
    if (roll.abs() > 180 || pitch.abs() > 180) return null;
    if (v2 &&
        ((bytes[12] & ~3) != 0 ||
            (bytes[12] & 2 != 0 && bytes[12] & 1 == 0) ||
            (signed(8) / 10).abs() > 180 ||
            (signed(10) / 10).abs() > 900)) return null;
    return SensorStatus(
        state: bytes[2],
        motion: bytes[3],
        roll: roll,
        pitch: pitch,
        yaw: v2 ? signed(8) / 10 : null,
        turnRate: v2 ? signed(10) / 10 : null,
        gyroAvailable: v2 && (bytes[12] & 1) != 0,
        gyroFresh: v2 && (bytes[12] & 2) != 0,
        receivedAt: DateTime.now());
  }
}
