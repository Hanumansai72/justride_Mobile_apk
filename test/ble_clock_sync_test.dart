import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/services/bluetooth_service.dart';

void main() {
  test('CTS sync includes full local calendar and 24-hour time', () {
    expect(
      JustRideBleService.encodeCurrentTime(DateTime(2026, 10, 19, 23, 59, 58)),
      [0xea, 0x07, 10, 19, 23, 59, 58, 1, 0, 1],
    );
  });

  test('CTS keeps leap day and year rollover', () {
    expect(
      JustRideBleService.encodeCurrentTime(DateTime(2028, 2, 29)),
      [0xec, 0x07, 2, 29, 0, 0, 0, 2, 0, 1],
    );
    expect(
      JustRideBleService.encodeCurrentTime(DateTime(2027, 1, 1)),
      [0xeb, 0x07, 1, 1, 0, 0, 0, 5, 0, 1],
    );
  });
}
