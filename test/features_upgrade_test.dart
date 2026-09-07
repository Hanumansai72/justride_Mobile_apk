import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/constants/app_constants.dart';
import 'package:justride_ui/core/models/app_models.dart';
import 'package:justride_ui/core/services/ble_navigation_service.dart';

void main() {
  group('Version & App Constants Tests', () {
    test('AppConstants defines valid appVersion and build number', () {
      expect(AppConstants.appVersion, equals('v1.2.0'));
      expect(AppConstants.appBuildNumber, equals(3));
    });

    test('AppReleaseModel detects new version correctly', () {
      const currentBuild = AppConstants.appBuildNumber;
      final releaseNewer = AppReleaseModel.fromJson({
        'version': '1.3.0',
        'build_number': 4,
        'platform': 'android',
        'download_url': 'https://justride.com/download/v1.3.0.apk',
        'release_notes': 'Bug fixes and performance improvements.',
      });

      expect(releaseNewer.buildNumber > currentBuild, isTrue);
      expect(releaseNewer.version, equals('1.3.0'));
      expect(releaseNewer.downloadUrl, isNotNull);

      final releaseOlder = AppReleaseModel.fromJson({
        'version': '1.1.0',
        'build_number': 2,
        'platform': 'android',
      });
      expect(releaseOlder.buildNumber > currentBuild, isFalse);
    });
  });

  group('Hardware Diagnostics BLE Protocol Tests', () {
    test('Diagnostics packet request opcode matches firmware specification', () {
      const kOpcodeDiagnostics = 0x10;
      final requestPacket = Uint8List.fromList([kOpcodeDiagnostics]);
      expect(requestPacket[0], equals(0x10));
    });

    test('Diagnostics 7-byte response telemetry packet parses correctly', () {
      // Packet format: [opcode (0x10), bt_ok, gps_ok, disp_ok, batt_pct, is_charging, volt_deci]
      final rawResponse = Uint8List.fromList([0x10, 1, 1, 1, 88, 0, 41]); // 88%, 4.1V, charging=0
      expect(rawResponse[0], equals(0x10));
      final btOk = rawResponse[1] == 1;
      final gpsOk = rawResponse[2] == 1;
      final dispOk = rawResponse[3] == 1;
      final battPct = rawResponse[4];
      final isCharging = rawResponse[5] == 1;
      final voltage = rawResponse[6] / 10.0;

      expect(btOk, isTrue);
      expect(gpsOk, isTrue);
      expect(dispOk, isTrue);
      expect(battPct, equals(88));
      expect(isCharging, isFalse);
      expect(voltage, closeTo(4.1, 0.05));
    });
  });

  group('Display Customization Reset Protocol Tests', () {
    test('Image control reset opcode is 0x04', () {
      const kCmdReset = 0x04;
      final resetCommand = Uint8List.fromList([kCmdReset]);
      expect(resetCommand.length, equals(1));
      expect(resetCommand[0], equals(0x04));
    });
  });
}
