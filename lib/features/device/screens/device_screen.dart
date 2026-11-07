import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/ble_navigation_service.dart';
import '../../../shared/widgets/visible_page_polling.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../widgets/device_action_tile.dart';
import 'device_pairing_screen.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen>
    with VisiblePagePolling<DeviceScreen> {
  final int _navIndex = 2; // Device is index 2
  DeviceModel? _device;
  bool _isLoading = true;
  double? _brightnessDraft;

  @override
  void initState() {
    super.initState();
    _fetchDevice();
  }

  @override
  Future<void> pollVisiblePage() async {
    if (_device != null) await _verifyDeviceStatus();
  }

  Future<void> _fetchDevice() async {
    setState(() => _isLoading = true);
    final res = await BackendService.instance.getMyDevice();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if ((res.success || res.isTransientFailure) && res.data != null) {
          _device = res.data;
        } else {
          if (!res.isTransientFailure) {
            _device = null;
          }
          if (res.errors?['reason'] == 'DEVICE_BLOCKED' ||
              res.message.contains('blocked')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 5),
                content: Row(
                  children: [
                    const Icon(Icons.block_rounded,
                        color: AppColors.textPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        res.message.isNotEmpty
                            ? res.message
                            : 'Device has been blocked and disconnected.',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      });
      if (res.isTransientFailure) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(res.message)));
      }
    }
  }

  Future<void> _verifyDeviceStatus() async {
    final res = await BackendService.instance.getMyDevice();
    if (res.isTransientFailure) return;
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _device = null;
      });
      if (res.errors?['reason'] == 'DEVICE_BLOCKED' ||
          res.message.contains('blocked')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
            content: Row(
              children: [
                const Icon(Icons.block_rounded, color: AppColors.textPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    res.message.isNotEmpty
                        ? res.message
                        : 'Device has been blocked by administrator. Disconnected.',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      setState(() {
        _device = res.data;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // If no device is connected or device is blocked, show the radar scanning/pairing screen
    if (BackendService.instance.accountPaired.value == false) {
      return const DevicePairingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _DeviceAppBar(),
      body: _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 2) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/places');
          } else if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/profile');
          }
        },
      ),
    );
  }

  Widget _buildBody() => RefreshIndicator(
        onRefresh: _fetchDevice,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Image.asset('assets/justride-device.png',
                  width: 100, height: 112, fit: BoxFit.contain),
              const SizedBox(width: 18),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_device?.deviceName ?? 'JustRide',
                        style: AppTextStyles.headingLarge, maxLines: 3),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<BluetoothConnectionState>(
                      valueListenable:
                          JustRideBleService.instance.connectionStateNotifier,
                      builder: (context, _, child) {
                        final connected =
                            JustRideBleService.instance.isDeviceConnected;
                        return Text(
                            connected
                                ? 'Connected'
                                : 'Offline · paired to your account',
                            style: TextStyle(
                                color: connected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontSize: 13));
                      },
                    ),
                  ])),
            ]),
            const SizedBox(height: 24),
            ValueListenableBuilder<BluetoothConnectionState>(
              valueListenable:
                  JustRideBleService.instance.connectionStateNotifier,
              builder: (context, connection, _) => _brightnessControl(),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<String?>(
              valueListenable: BleNavigationService.instance.firmwareVersion,
              builder: (context, _, child) =>
                  BleNavigationService.instance.photoUploadSupported
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DeviceActionTile(
                            icon: Icons.photo_outlined,
                            title: 'Display photo',
                            onTap: () => Navigator.of(context)
                                .pushNamed('/display-customization'),
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
            DeviceActionTile(
                icon: Icons.tune_outlined,
                title: 'Hardware settings',
                onTap: () =>
                    Navigator.of(context).pushNamed('/device-settings')),
            const SizedBox(height: 20),
            ValueListenableBuilder<String?>(
              valueListenable: BleNavigationService.instance.firmwareVersion,
              builder: (context, version, _) => Text(
                  'Firmware ${version ?? _device?.firmwareVersion ?? '—'}',
                  style: AppTextStyles.bodyMedium),
            ),
          ],
        ),
      );

  Widget _brightnessControl() {
    final ble = BleNavigationService.instance;
    final connected = JustRideBleService.instance.isDeviceConnected;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ValueListenableBuilder<int>(
                valueListenable: ble.manualBrightness,
                builder: (context, value, _) {
                  final shown = _brightnessDraft ?? value.toDouble();
                  return Column(children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Display brightness',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600))),
                      Text('${shown.round()}%',
                          style: const TextStyle(
                              fontSize: 20, color: AppColors.primary))
                    ]),
                    Slider(
                        value: shown.clamp(0, 100),
                        min: 0,
                        max: 100,
                        label: '${shown.round()}%',
                        onChanged: connected
                            ? (value) =>
                                setState(() => _brightnessDraft = value)
                            : null,
                        onChangeEnd: connected
                            ? (value) async {
                                final sent =
                                    await ble.sendSetBrightness(value.round());
                                if (!mounted || !context.mounted) return;
                                setState(() => _brightnessDraft = null);
                                if (!sent)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Could not adjust brightness. Reconnect and retry.')));
                              }
                            : null),
                  ]);
                }),
            if (!connected)
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Connect the display to adjust brightness.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13))),
            const Divider(height: 20),
            ValueListenableBuilder<bool>(
                valueListenable: ble.automaticBrightness,
                builder: (context, value, _) => SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic day/night'),
                    subtitle: const Text('85% by day · 35% at night'),
                    value: value,
                    onChanged: ble.setAutomaticBrightness)),
          ])),
    );
  }
}

class _DeviceAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => AppBar(
        title: const Text('Your device'),
        centerTitle: false,
        actions: [
          IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_none_outlined),
              onPressed: () =>
                  Navigator.of(context).pushNamed('/notifications'))
        ],
      );
}
