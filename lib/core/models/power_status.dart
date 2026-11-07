/// Stock Waveshare power telemetry. VCC is not battery voltage during USB power.
class PowerStatus {
  final int? railMillivolts, batteryMillivolts, percentage;
  final int source, charging;
  final DateTime receivedAt;
  const PowerStatus(
      {this.railMillivolts,
      this.batteryMillivolts,
      this.percentage,
      required this.source,
      required this.charging,
      required this.receivedAt});
  bool get estimated => percentage != null;
  String get levelLabel => percentage == null ? '—' : '~$percentage%';
  String get sourceLabel => source == 1
      ? 'Battery power (inferred)'
      : source == 2
          ? 'USB power (inferred)'
          : 'Power source unknown';
  String get chargingLabel => charging == 1
      ? 'Charging'
      : charging == 2
          ? 'Full'
          : charging == 0
              ? 'Not charging'
              : 'Charging status unavailable';
  String get voltageLabel => railMillivolts == null
      ? 'Voltage unavailable'
      : '${(railMillivolts! / 1000).toStringAsFixed(2)} V supply';
  String get detailLabel => '$sourceLabel · $voltageLabel';
  bool freshAt(DateTime now) =>
      now.difference(receivedAt) < const Duration(seconds: 15);
  static PowerStatus? parse(List<int> p, {DateTime? now}) {
    if (p.length != 10 ||
        p.any((b) => b < 0 || b > 255) ||
        p[0] != 0x1d ||
        p[1] != 1 ||
        (p[2] & ~3) != 0 ||
        p[3] > 2 ||
        ![0, 1, 2, 255].contains(p[4]) ||
        (p[5] > 100 && p[5] != 255)) return null;
    final rail = p[6] | p[7] << 8, battery = p[8] | p[9] << 8;
    final valid = (p[2] & 1) != 0, estimate = (p[2] & 2) != 0;
    if (valid && (rail < 2800 || rail > 5500)) return null;
    if (!valid &&
        (rail != 0 || battery != 0 || p[3] != 0 || estimate || p[5] != 255))
      return null;
    if (estimate &&
        (!valid ||
            p[3] != 1 ||
            battery != rail ||
            battery < 3000 ||
            battery > 4300 ||
            p[5] > 100)) return null;
    if (!estimate && (battery != 0 || p[5] != 255)) return null;
    return PowerStatus(
        railMillivolts: valid ? rail : null,
        batteryMillivolts: estimate ? battery : null,
        percentage: estimate ? p[5] : null,
        source: p[3],
        charging: p[4],
        receivedAt: now ?? DateTime.now());
  }
}
