import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/services/app_update_service.dart';
import '../../../shared/widgets/app_logo.dart';

class AppUpdateScreen extends StatelessWidget {
  const AppUpdateScreen({super.key, this.gated = false});
  final bool gated;

  @override
  Widget build(BuildContext context) {
    final updates = AppUpdateService.instance;
    return ListenableBuilder(
        listenable: updates,
        builder: (context, _) {
          final blocked = gated || updates.required;
          return PopScope(
            canPop: !blocked,
            child: Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                automaticallyImplyLeading: !blocked,
                title: const Text('App update'),
                actions: [
                  Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: AppLogo(fontSize: 14))
                ],
              ),
              body: SafeArea(
                  child: Center(
                      child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 28),
                        Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(24)),
                            child: const Icon(Icons.system_update_rounded,
                                size: 40, color: AppColors.primary)),
                        const SizedBox(height: 28),
                        Text(
                            updates.checking && !updates.verified
                                ? 'Checking for updates'
                                : updates.hasUpdate
                                    ? 'An update is ready.'
                                    : updates.error != null
                                        ? 'Let’s try that again.'
                                        : 'You’re up to date.',
                            style: const TextStyle(
                                fontSize: 32,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 16),
                        Text(
                            updates.hasUpdate
                                ? updates.required
                                    ? 'Please update the JustRide app to continue.'
                                    : 'A new update is available. Install it when you’re ready.'
                                : updates.checking
                                    ? 'This will only take a moment.'
                                    : updates.error != null
                                        ? 'Connect to the internet so we can check the app version.'
                                        : 'You have the latest available JustRide app.',
                            style: const TextStyle(
                                fontSize: 16,
                                height: 1.6,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 28),
                        if (updates.hasUpdate)
                          Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.border)),
                              child: Row(children: [
                                const Icon(Icons.verified_outlined,
                                    color: AppColors.primary),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      const Text('JustRide for Android',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(
                                          updates.required
                                              ? 'Update required'
                                              : 'Ready to install',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary)),
                                    ])),
                              ])),
                        if (updates.error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(updates.error!,
                                  style: const TextStyle(
                                      color: AppColors.errorText))),
                        const SizedBox(height: 32),
                        SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton.icon(
                              onPressed: updates.checking || updates.opening
                                  ? null
                                  : updates.hasUpdate
                                      ? updates.install
                                      : updates.check,
                              icon: updates.checking || updates.opening
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Icon(updates.hasUpdate
                                      ? Icons.download_rounded
                                      : Icons.refresh_rounded),
                              label: Text(updates.opening
                                  ? 'Opening installer…'
                                  : updates.hasUpdate
                                      ? 'Install update'
                                      : updates.checking
                                          ? 'Checking…'
                                          : 'Check again'),
                            )),
                        if (updates.hasUpdate)
                          const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text(
                                  'Download the APK, then confirm installation on your phone.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                      color: AppColors.textSecondary))),
                        if (!blocked)
                          Center(
                              child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  child: const Text('Not now'))),
                        const SizedBox(height: 32),
                      ],
                    )),
              ))),
            ),
          );
        });
  }
}

/// A root overlay cannot be bypassed by back, deep links, or device pairing.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;
  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  @override
  void initState() {
    super.initState();
    AppUpdateService.instance.init();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppUpdateService.instance,
        builder: (_, __) => Stack(children: [
          Offstage(
              offstage: AppUpdateService.instance.blockAccess,
              child: widget.child),
          if (AppUpdateService.instance.blockAccess)
            const Positioned.fill(child: AppUpdateScreen(gated: true)),
        ]),
      );
}
