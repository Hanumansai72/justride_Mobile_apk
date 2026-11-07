import 'package:flutter/foundation.dart';
import '../../../core/services/notification_listener_service.dart';
import '../../../core/services/phone_turn_alerts.dart';
import '../../../app/theme/app_colors.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/services/ota_service.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/models/app_models.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/device_unlink_dialog.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/ble_navigation_service.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';

// â”€â”€ Colour tokens matching the HTML design â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SC {
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const textSec = AppColors.textSecondary;
  static const errorRed = AppColors.errorLight;
  static const surfCont = AppColors.surfaceElevated;
}

class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar:
            AppBar(title: const Text('Hardware settings'), centerTitle: false),
        bottomNavigationBar: JustRideBottomNavBar(
            currentIndex: 2,
            onTap: (index) {
              const routes = ['/dashboard', '/places', '/device', '/profile'];
              Navigator.of(context).pushReplacementNamed(routes[index]);
            }),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _group('Ride and display', [
                ValueListenableBuilder<bool>(
                    valueListenable: BleNavigationService.instance.gloveMode,
                    builder: (context, value, _) => SwitchListTile.adaptive(
                        title: const Text('Larger riding controls'),
                        value: value,
                        onChanged: BleNavigationService.instance.setGloveMode)),
                ValueListenableBuilder<int>(
                    valueListenable: BleNavigationService.instance.sleepMinutes,
                    builder: (context, value, _) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(children: [
                          const Expanded(
                              child: Text('Display sleep',
                                  style: TextStyle(fontSize: 16))),
                          DropdownButton<int>(
                              value: value,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(
                                    value: 1, child: Text('1 minute')),
                                DropdownMenuItem(
                                    value: 5, child: Text('5 minutes')),
                                DropdownMenuItem(
                                    value: 10, child: Text('10 minutes')),
                                DropdownMenuItem(
                                    value: 0, child: Text('Always awake')),
                              ],
                              onChanged: (next) {
                                if (next != null)
                                  BleNavigationService.instance
                                      .setSleepMinutes(next);
                              }),
                        ]))),
                ValueListenableBuilder<bool>(
                    valueListenable: PhoneTurnAlerts.enabled,
                    builder: (context, value, _) => SwitchListTile.adaptive(
                        title: const Text('Phone turn vibration'),
                        value: value,
                        onChanged: PhoneTurnAlerts.setEnabled)),
              ]),
              _group('Phone connection', [
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                  ValueListenableBuilder<bool>(
                      valueListenable:
                          JustRideBleService.instance.companionEnabled,
                      builder: (context, value, _) => SwitchListTile.adaptive(
                          title: const Text('Reconnect automatically'),
                          value: value,
                          onChanged: (enabled) async {
                            if (!enabled) {
                              await JustRideBleService.instance
                                  .disableCompanion();
                              return;
                            }
                            final ok = await JustRideBleService.instance
                                .enableCompanion();
                            if (!ok && context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(JustRideBleService
                                          .instance.companionError.value ??
                                      'Connect your paired display first.')));
                          })),
                ValueListenableBuilder<bool>(
                    valueListenable:
                        NotificationListenerService.instance.displayEnabled,
                    builder: (context, value, _) => SwitchListTile.adaptive(
                        title: const Text('Phone notifications'),
                        value: value,
                        onChanged: NotificationListenerService
                            .instance.setDisplayEnabled)),
                ValueListenableBuilder<int>(
                    valueListenable: BleNavigationService.instance.mediaState,
                    builder: (context, state, _) => ListTile(
                        title: const Text('Music controls'),
                        subtitle: Text(state == 1
                            ? 'Notification Access is required'
                            : state >= 3 && state <= 5
                                ? 'Connected to phone music'
                                : 'Connect your music player'),
                        trailing: TextButton(
                            onPressed:
                                BleNavigationService.instance.connectMusic,
                            child: Text(state == 1 ? 'Enable' : 'Connect')))),
              ]),
              const SizedBox(height: 4),
              Text('Software', style: AppTextStyles.headingSmall),
              const SizedBox(height: 12),
              ValueListenableBuilder<String?>(
                  valueListenable:
                      BleNavigationService.instance.firmwareVersion,
                  builder: (context, version, _) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Installed firmware'),
                      subtitle: Text(version ??
                          'Connect the display to read its version'))),
              _FirmwareUpdateCard(),
              const SizedBox(height: 24),
              _group('Device actions', [
                ListTile(
                    title: const Text('Restart device'),
                    leading: const Icon(Icons.restart_alt),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _confirmRestartDevice(context)),
                ListTile(
                    title: const Text('Reset display preferences'),
                    leading: const Icon(Icons.restore),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _confirmResetDevice(context)),
              ]),
              _DisconnectButton(),
              const SizedBox(height: 8),
              _UnlinkButton(),
            ]),
      );

  Widget _group(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.headingSmall),
          const SizedBox(height: 12),
          Material(
              clipBehavior: Clip.antiAlias,
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: Column(children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  children[i],
                ]
              ])),
        ]),
      );

  void _confirmRestartDevice(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SC.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _SC.cardBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.restart_alt_rounded, color: _SC.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Restart Device?',
              style: TextStyle(
                fontFamily: 'Stack Sans Text',
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'This will restart the JustRide motorcycle cockpit HUD display.',
          style: TextStyle(
              fontFamily: 'Stack Sans Text', color: _SC.textSec, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL',
                style: TextStyle(
                    fontFamily: 'Stack Sans Text', color: _SC.textSec)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok =
                  await BleNavigationService.instance.sendRestartDevice();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Restart command sent to JustRide HUD'
                        : 'Device not connected via Bluetooth'),
                    backgroundColor: ok ? _SC.primary : _SC.errorRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _SC.primary,
              foregroundColor: _SC.onPrimary,
            ),
            child: Text(
              'RESTART',
              style: TextStyle(
                  fontFamily: 'Stack Sans Text', fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmResetDevice(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SC.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _SC.cardBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: _SC.errorRed, size: 24),
            const SizedBox(width: 8),
            Text(
              'Reset to Defaults?',
              style: TextStyle(
                fontFamily: 'Stack Sans Text',
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'This will reset the HUD display brightness (70%), recenter navigation camera, and return to Home screen.',
          style: TextStyle(
              fontFamily: 'Stack Sans Text', color: _SC.textSec, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL',
                style: TextStyle(
                    fontFamily: 'Stack Sans Text', color: _SC.textSec)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await BleNavigationService.instance.sendResetDevice();
              await BleNavigationService.instance.sendSetBrightness(70);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Reset command sent to JustRide HUD'
                        : 'Device not connected via Bluetooth'),
                    backgroundColor: ok ? _SC.primary : _SC.errorRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _SC.errorRed,
              foregroundColor: Colors.black,
            ),
            child: Text(
              'RESET',
              style: TextStyle(
                  fontFamily: 'Stack Sans Text', fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Device Identity Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _FirmwareUpdateCard extends StatefulWidget {
  @override
  State<_FirmwareUpdateCard> createState() => _FirmwareUpdateCardState();
}

class _FirmwareUpdateCardState extends State<_FirmwareUpdateCard> {
  FirmwareReleaseModel? _latestRelease;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLatestRelease();
  }

  Future<void> _fetchLatestRelease() async {
    try {
      final res = await BackendService.instance.getLatestFirmwareRelease();
      if (mounted && res.success && res.data != null) {
        setState(() {
          _latestRelease = res.data;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _showOtaModal(BuildContext context) {
    final dev = JustRideBleService.instance.connectedDevice;
    if (dev == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please connect to JustRide device over Bluetooth first.'),
          backgroundColor: _SC.errorRed,
        ),
      );
      return;
    }

    final targetVer = _latestRelease?.version ??
        BleNavigationService.instance.firmwareVersion.value ??
        'Bundled firmware';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<OtaProgress>(
          valueListenable: JustRideOtaService.instance.progressNotifier,
          builder: (context, progress, _) {
            final isDone = progress.state == OtaState.success;
            final isFailed = progress.state == OtaState.failed;

            return AlertDialog(
              backgroundColor: _SC.cardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Firmware Update (v$targetVer)',
                style: AppTextStyles.headingMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    progress.statusMessage,
                    style:
                        AppTextStyles.bodyMedium.copyWith(color: _SC.textSec),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress.progress.clamp(0.0, 1.0).toDouble(),
                    backgroundColor: _SC.surfCont,
                    color: _SC.primary,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(progress.progress * 100).round()}% Complete',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: _SC.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (progress.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Error: ${progress.error}',
                      style: const TextStyle(color: _SC.errorRed, fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                if (isDone || isFailed)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close',
                        style: TextStyle(color: _SC.primary)),
                  )
                else
                  TextButton(
                    onPressed: () {
                      JustRideOtaService.instance.cancelUpdate();
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Cancel',
                        style: TextStyle(color: _SC.textSec)),
                  ),
              ],
            );
          },
        );
      },
    );

    // If download_url exists from backend, download & flash. Otherwise fallback to bundled binary.
    () async {
      try {
        final downloadUrl = _latestRelease?.fileUrl;
        if (downloadUrl != null && downloadUrl.startsWith('http')) {
          await JustRideOtaService.instance.downloadAndFlashFirmware(
            device: dev,
            downloadUrl: downloadUrl,
            deviceId: dev.remoteId.str,
            targetVersion: targetVer,
          );
        } else {
          final asset = BleNavigationService.instance.firmwareChipId == 9
              ? 'assets/firmware/justride_s3_amoled143.bin'
              : 'assets/firmware/justride_firmware.bin';
          final byteData = await rootBundle.load(asset);
          final realFirmwareBytes = byteData.buffer.asUint8List();
          debugPrint(
              '[OTA] Loaded bundled firmware binary: ${realFirmwareBytes.length} bytes, magic: 0x${realFirmwareBytes[0].toRadixString(16)}');
          await JustRideOtaService.instance.flashFirmware(
            device: dev,
            firmwareBytes: realFirmwareBytes,
          );
        }
      } catch (err) {
        debugPrint('[OTA] Error starting firmware flash: $err');
        JustRideOtaService.instance.progressNotifier.value = OtaProgress(
          state: OtaState.failed,
          progress: 0.0,
          statusMessage: 'Update unavailable',
          error: 'Unable to prepare the update. Restart the app and try again.',
        );
      }
    }();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.system_update_outlined, size: 22),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Text('Firmware update', style: AppTextStyles.headingSmall))
          ]),
          const SizedBox(height: 12),
          if (_isLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_latestRelease != null)
            Text('Available release ${_latestRelease!.version}',
                style: AppTextStyles.bodyMedium),
          if (_latestRelease?.releaseNotes?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(_latestRelease!.releaseNotes!,
                style: AppTextStyles.bodyMedium),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _isLoading ? null : () => _showOtaModal(context),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Install firmware')),
        ]),
      );
}

class _DisconnectButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BluetoothConnectionState>(
      valueListenable: JustRideBleService.instance.connectionStateNotifier,
      builder: (context, connState, _) {
        final isConnected = connState == BluetoothConnectionState.connected ||
            JustRideBleService.instance.isDeviceConnected;

        return Center(
          child: OutlinedButton.icon(
            onPressed: () async {
              if (isConnected) {
                await JustRideBleService.instance.disconnectDevice();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Bluetooth disconnected. Device remains paired to your account.'),
                      duration: Duration(seconds: 3),
                      backgroundColor: _SC.surfCont,
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Searching for your JustRide deviceâ€¦'),
                      duration: Duration(seconds: 2),
                      backgroundColor: _SC.primary,
                    ),
                  );
                }
                final bleAddress =
                    await JustRideBleService.instance.loadSavedBleAddress();
                final ok = await JustRideBleService.instance
                    .reconnect(targetBleAddress: bleAddress);
                if (context.mounted) {
                  final err =
                      JustRideBleService.instance.lastBleErrorNotifier.value;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Reconnected & real-time clock synced!'
                          : (err ??
                              (bleAddress != null
                                  ? 'Could not find device ($bleAddress). Ensure it is nearby.'
                                  : 'No paired device found. Please pair first.'))),
                      duration: const Duration(seconds: 3),
                      backgroundColor: ok ? _SC.primary : _SC.errorRed,
                    ),
                  );
                }
              }
            },
            icon: Icon(
              isConnected
                  ? Icons.bluetooth_disabled_rounded
                  : Icons.bluetooth_connected_rounded,
              color: isConnected ? _SC.textSec : _SC.primary,
              size: 20,
            ),
            label: Text(
              isConnected ? 'Disconnect Bluetooth' : 'Reconnect Bluetooth',
              style: AppTextStyles.bodyLarge.copyWith(
                color: isConnected ? _SC.textSec : _SC.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: isConnected ? _SC.cardBorder : _SC.primary,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingLg,
                vertical: AppConstants.spacingSm,
              ),
            ),
          ),
        );
      },
    );
  }
}

// â”€â”€ Unlink Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _UnlinkButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final result = await BackendService.instance.getMyDevice();
          if (!context.mounted) return;
          final device = result.data;
          if (!result.success || device == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(result.success
                    ? 'No linked device found.'
                    : result.message)));
            return;
          }
          final done = await showDeviceUnlinkDialog(context,
              deviceId: device.id, deviceName: device.deviceName);
          if (done && context.mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/dashboard', (_) => false);
          }
        },
        icon: const Icon(Icons.link_off_rounded, color: _SC.errorRed, size: 20),
        label: Text(
          'Unlink Device',
          style: AppTextStyles.bodyLarge.copyWith(
            color: _SC.errorRed,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMd,
            vertical: AppConstants.spacingSm,
          ),
        ),
      ),
    );
  }
}
