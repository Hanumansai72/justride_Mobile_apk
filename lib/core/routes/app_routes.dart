import 'package:flutter/material.dart';

// Screens
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';

import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/dashboard/screens/home_screen.dart';
import '../../features/trips/screens/trips_screen.dart';
import '../../features/places/screens/places_screen.dart';
import '../../features/places/screens/add_place_screen.dart';
import '../../features/device/screens/device_screen.dart';
import '../../features/navigation/screens/active_navigation_screen.dart';
import '../../features/navigation/screens/go_screen.dart';


import '../../features/device/screens/device_settings_screen.dart';
import '../../features/device/screens/device_pairing_screen.dart';
import '../../features/device/screens/display_customization_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/profile_settings_screen.dart';
import '../../features/profile/screens/notifications_screen.dart';
import '../../features/profile/screens/help_support_screen.dart';
import '../../features/profile/screens/my_tickets_screen.dart';
import '../../features/profile/screens/support_ticket_screen.dart';
import '../../features/profile/screens/about_screen.dart';
import '../../features/profile/screens/delete_account_screen.dart';

/// Central Route Registry for the JustRide application.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  
  static const String dashboard = '/dashboard';
  static const String home = '/home';
  static const String places = '/places';
  static const String addPlace = '/add-place';
  static const String trips = '/trips';
  static const String activeNavigation = '/active-navigation';
  static const String go = '/go';

  
  static const String device = '/device';
  static const String deviceSettings = '/device-settings';
  static const String devicePairing = '/pair-device';
  static const String displayCustomization = '/display-customization';
  
  static const String profile = '/profile';
  static const String profileSettings = '/profile-settings';
  static const String notifications = '/notifications';
  static const String helpSupport = '/help';
  static const String myTickets = '/my-tickets';
  static const String supportTicket = '/support-ticket';
  static const String about = '/about';
  static const String deleteAccount = '/delete-account';

  /// Map of all named routes to widget builders
  static Map<String, WidgetBuilder> get routes => {
    splash: (context) => const SplashScreen(),
    login: (context) => const LoginScreen(),
    signup: (context) => const SignupScreen(),
    forgotPassword: (context) => const ForgotPasswordScreen(),
    resetPassword: (context) => const ResetPasswordScreen(),

    
    dashboard: (context) => const DashboardScreen(),
    home: (context) => const HomeScreen(),
    places: (context) => const PlacesScreen(),
    addPlace: (context) => const AddPlaceScreen(),
    trips: (context) => const TripsScreen(),
    activeNavigation: (context) => const ActiveNavigationScreen(),
    go: (context) => const GoScreen(),


    
    device: (context) => const DeviceScreen(),
    deviceSettings: (context) => const DeviceSettingsScreen(),
    devicePairing: (context) => const DevicePairingScreen(),
    displayCustomization: (context) => const DisplayCustomizationScreen(),
    
    profile: (context) => const ProfileScreen(),
    profileSettings: (context) => const ProfileSettingsScreen(),
    notifications: (context) => const NotificationsScreen(),
    helpSupport: (context) => const HelpSupportScreen(),
    myTickets: (context) => const MyTicketsScreen(),
    supportTicket: (context) => const SupportTicketScreen(),
    about: (context) => const AboutScreen(),
    deleteAccount: (context) => const DeleteAccountScreen(),
  };
}
