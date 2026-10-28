/// Live MPU telemetry on FF32. Roll/pitch are signed tenths of a degree.
class SensorStatus {
  final int state, motion;
  final double roll, pitch;
  final DateTime receivedAt;
  const SensorStatus(
      {required this.state,
      required this.motion,
      required this.roll,
      required this.pitch,
      required this.receivedAt});

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
    if (bytes.length != 8 ||
        bytes[0] != 0x1a ||
        bytes[1] != 1 ||
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
    return SensorStatus(
        state: bytes[2],
        motion: bytes[3],
        roll: roll,
        pitch: pitch,
        receivedAt: DateTime.now());
  }
}
