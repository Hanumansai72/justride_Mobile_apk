import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Draft status remains visible; internal review notes live in docs/legal-review-notes.md.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.isPrivacy});

  final bool isPrivacy;

  @override
  Widget build(BuildContext context) {
    final sections = isPrivacy ? _privacy : _terms;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isPrivacy ? 'Privacy Policy' : 'Terms & Conditions'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text(
                  'Draft for legal review — not yet effective. '
                  'For questions, contact Help & Support.',
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              const SizedBox(height: AppConstants.spacingLg),
              for (var i = 0; i < sections.length; i++) ...[
                Semantics(
                  header: true,
                  child: Text('${i + 1}. ${sections[i].$1}',
                      style: AppTextStyles.headingSmall),
                ),
                const SizedBox(height: AppConstants.spacingSm),
                Text(sections[i].$2, style: AppTextStyles.bodyMedium),
                const SizedBox(height: AppConstants.spacingLg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _terms = <(String, String)>[
  (
    'Introduction and acceptance',
    'These proposed terms describe use of the JustRide application and its connected navigation device. This draft is not yet effective.'
  ),
  (
    'Eligibility and responsibilities',
    'Use the service only when legally permitted and provide accurate account information. You are responsible for complying with road rules and using features safely.'
  ),
  (
    'Account registration and security',
    'The application supports registration, password-based login and Google sign-in. Protect your credentials and phone, and report suspected unauthorized access through Help & Support. Do not use another person\'s account without authorization.'
  ),
  (
    'Device and application usage',
    'Pair only a device you are authorized to use. Available functions include navigation, display customization, device settings and firmware updates. Feature access depends on the device, firmware, phone and permissions. Follow the instructions presented during setup and updates.'
  ),
  (
    'Bluetooth connectivity',
    'Connected features require a compatible paired device and Bluetooth permissions. Range, interference, battery state and phone settings can interrupt communication. Do not rely on continuous delivery of directions or notifications.'
  ),
  (
    'Navigation accuracy and limitations',
    'Routes, maps, distances, timing and speed estimates depend on location signals and external map services. They may be delayed, incomplete or inaccurate and may not reflect closures or current road conditions. Check signs and your surroundings and use your own judgment.'
  ),
  (
    'Road safety',
    'Set destinations and adjust settings while safely stopped. Keep attention on the road and control of your motorcycle. Do not interact with calls, notifications or the application when doing so would distract you. JustRide is not an emergency service or a substitute for safe riding.'
  ),
  (
    'Availability and connectivity',
    'Account services, route requests, search and downloads depend on network access and service availability. Mobile data charges may apply. Phone power management, revoked permissions or service interruptions can limit features.'
  ),
  (
    'Intellectual property',
    'Use of the app does not transfer ownership of the JustRide brand, software or other protected material. Third-party software and map content remain subject to their respective notices and terms. Third-party notices are available from Help & Support.'
  ),
  (
    'Prohibited activities',
    'Do not attempt unauthorized access, interfere with services or other users, bypass account or device access controls, upload unlawful content, or use the service for unlawful purposes. Restrictions must respect rights that cannot lawfully be restricted.'
  ),
  (
    'Disclaimers and liability',
    'Navigation and connectivity limitations described above should be considered before use. This draft sets no liability cap and does not exclude mandatory consumer rights.'
  ),
  (
    'Changes to services or terms',
    'App updates, firmware and external services may change available features.'
  ),
  (
    'Account termination',
    'You can request account deletion through Profile > Delete Account. Account and device access restrictions may apply.'
  ),
  (
    'Contact and support',
    'Use Profile > Help & Support to submit a support ticket.'
  ),
];

const _privacy = <(String, String)>[
  (
    'Introduction',
    'This draft describes how information supports JustRide features. Processing depends on the features you use and the permissions you grant.'
  ),
  (
    'Information collected',
    'JustRide features use account details, paired-device information, location and navigation information, saved places, trip records, support messages and selected display images. Optional phone and notification features can use caller information and notification content.'
  ),
  (
    'Account information',
    'Your account details are used to register and sign in. Google sign-in verifies your Google account. Sign-in information and your profile are stored on your phone to keep you signed in.'
  ),
  (
    'Device and Bluetooth information',
    'Pairing shares your device name, Bluetooth address and available device identifiers and versions with JustRide. Pairing information is saved on your phone for reconnection. Navigation, display settings, selected images and device updates are transferred to your paired device.'
  ),
  (
    'Location and navigation',
    'Location access supports route planning and turn-by-turn guidance. Background location is configured to keep navigation working while riding. Search and routing requests can send search text, coordinates, origins and destinations to external map services. Navigation information is also sent to the paired display. Active-session data is saved locally to support resuming navigation.'
  ),
  (
    'Ride history and usage',
    'JustRide shows your trip history and ride statistics and tracks distance, speed and duration during an active ride. Saved places include the labels, addresses and locations you choose to save.'
  ),
  (
    'How information is used',
    'Information supports sign-in, profiles, paired devices, navigation, session recovery, ride history, display customization and support requests. Support tickets include the content you submit. Selected display images can be uploaded to JustRide and transferred to your device.'
  ),
  (
    'Storage and retention',
    'Sign-in, profile, pairing and navigation information is stored on your phone. Account and feature records are also stored by JustRide services. Signing out does not delete all saved information. Use Delete Account or contact Help & Support for deletion questions.'
  ),
  (
    'Permissions and controls',
    'You can manage location, Bluetooth, notifications, phone permissions and notification access in phone settings. Revoking permissions may disable related features. Image selection uses the system image picker. With Android notification access, notification titles and text can be forwarded to the paired display. Phone permissions support incoming-call state, caller-number display and answering or rejecting calls.'
  ),
  (
    'Third-party services and sharing',
    'Google sign-in and map services support connected features. Google Fonts may fetch font files at runtime. Map search, geocoding and routing include fallback requests to Photon (Komoot), OpenStreetMap Nominatim and the OSRM routing service. These requests can include query text or coordinates. Shared map links may be resolved through their hosting services. Selected display images can be uploaded through an image-hosting service. Data required for connected features is sent over Bluetooth to the paired device.'
  ),
  (
    'Data security',
    'Protect your phone and account credentials. Contact Help & Support if you suspect unauthorized access. No system can guarantee complete protection against unauthorized access.'
  ),
  (
    'Privacy rights',
    'The app provides profile editing, saved-place removal and an account-deletion request. Other rights and their conditions depend on applicable law.'
  ),
  (
    'Deletion requests',
    'Use Profile > Delete Account to request account deletion. After a successful request, the app signs you out and clears its sign-in information. Contact Help & Support for questions about deletion of saved information.'
  ),
  (
    'Policy changes',
    'This draft is under review and is not yet effective. Contact Help & Support for questions about privacy information.'
  ),
  (
    'Contact information',
    'In-app support is available through Profile > Help & Support.'
  ),
];
