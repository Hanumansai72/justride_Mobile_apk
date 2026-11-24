import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import 'bottom_nav_bar.dart';

/// One navigation bar for every linked-account page, including active rides.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    final index = switch (route) {
      '/places' || '/add-place' => -1,
      '/community' => 1,
      '/device' ||
      '/device-settings' ||
      '/pair-device' ||
      '/display-customization' =>
        2,
      '/dashboard' || '/home' || '/go' || '/active-navigation' || '/trips' => 0,
      _ => 3,
    };
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: child,
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : JustRideBottomNavBar(
              currentIndex: index,
              onTap: (selected) {
                const routes = [
                  '/dashboard',
                  '/community',
                  '/device',
                  '/profile'
                ];
                if (route == routes[selected]) return;
                Navigator.of(context)
                    .pushNamedAndRemoveUntil(routes[selected], (_) => false);
              }),
    );
  }
}
