import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'theme/app_colors.dart';
import '../core/routes/app_routes.dart';

/// Global Navigation Key for handling automatic session expiry redirects
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Root widget of the JustRide application.
/// Configures named routes so screens can be accessed directly by URL path.
class JustRideApp extends StatelessWidget {
  const JustRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'JustRide',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => kIsWeb
          ? ColoredBox(
              color: AppColors.backgroundInset,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: child!,
                ),
              ),
            )
          : child!,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
    );
  }
}
