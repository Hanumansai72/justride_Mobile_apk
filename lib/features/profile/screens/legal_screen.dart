import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Review-ready copy grounded in the current client implementation.
/// Resolve the visible review notes with the operator before publication.
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
                  'Draft for legal review — not yet effective. Before publication, '
                  'confirm the service operator, legal entity, address, contact details, '
                  'effective date and applicable jurisdiction. Review notes below remain unresolved.',
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
    'These proposed terms describe use of the JustRide application and its connected navigation device. '
        'Review before publication: identify the contracting operator, effective date, acceptance process and applicable law. '
        'This draft does not itself record user acceptance.'
  ),
  (
    'Eligibility and responsibilities',
    'Use the service only when legally permitted and provide accurate account information. '
        'You are responsible for complying with road rules and using features safely. '
        'Review before publication: confirm any minimum age and other eligibility conditions.'
  ),
  (
    'Account registration and security',
    'The application supports registration, password-based login and Google sign-in. '
        'Protect your credentials and phone, and report suspected unauthorized access through Help & Support. '
        'Do not use another person\'s account without authorization.'
  ),
  (
    'Device and application usage',
    'Pair only a device you are authorized to use. Available functions include navigation, display customization, '
        'device settings and firmware updates. Feature access depends on the device, firmware, phone and permissions. '
        'Follow the instructions presented during setup and updates.'
  ),
  (
    'Bluetooth connectivity',
    'Connected features require a compatible paired device and Bluetooth permissions. '
        'Range, interference, battery state and phone settings can interrupt communication. '
        'Do not rely on continuous delivery of directions or notifications.'
  ),
  (
    'Navigation accuracy and limitations',
    'Routes, maps, distances, timing and speed estimates depend on location signals and external map services. '
        'They may be delayed, incomplete or inaccurate and may not reflect closures or current road conditions. '
        'Check signs and your surroundings and use your own judgment.'
  ),
  (
    'Road safety',
    'Set destinations and adjust settings while safely stopped. Keep attention on the road and control of your motorcycle. '
        'Do not interact with calls, notifications or the application when doing so would distract you. '
        'JustRide is not an emergency service or a substitute for safe riding.'
  ),
  (
    'Availability and connectivity',
    'Account services, route requests, search and downloads depend on network access and service availability. '
        'Mobile data charges may apply. Phone power management, revoked permissions or service interruptions can limit features.'
  ),
  (
    'Intellectual property',
    'Use of the app does not transfer ownership of the JustRide brand, software or other protected material. '
        'Third-party software and map content remain subject to their respective notices and terms. '
        'Third-party notices are available from Help & Support. '
        'Review before publication: confirm ownership and the scope of the user license.'
  ),
  (
    'Prohibited activities',
    'Do not attempt unauthorized access, interfere with services or other users, bypass account or device access controls, '
        'upload unlawful content, or use the service for unlawful purposes. '
        'Restrictions must respect rights that cannot lawfully be restricted.'
  ),
  (
    'Disclaimers and liability',
    'Navigation and connectivity limitations described above should be considered before use. '
        'Review before publication: legal counsel must specify any permitted warranties, disclaimers and liability limits. '
        'This draft sets no liability cap and does not exclude mandatory consumer rights.'
  ),
  (
    'Changes to services or terms',
    'App updates, firmware and external services may change available features. '
        'Review before publication: confirm how changes to terms will be communicated, when they take effect '
        'and whether renewed acceptance is needed.'
  ),
  (
    'Account termination',
    'You can request account deletion through Profile > Delete Account. The client also handles account and device access restrictions. '
        'Review before publication: confirm suspension and termination grounds, notice, appeal procedures and data-retention consequences.'
  ),
  (
    'Contact and support',
    'Use Profile > Help & Support to submit a support ticket. '
        'Review before publication: add a verified legal contact, postal address and an alternative contact method '
        'for people who cannot sign in.'
  ),
];

const _privacy = <(String, String)>[
  (
    'Introduction',
    'This draft describes data flows found in the current JustRide client. Actual processing depends on the features you use '
        'and permissions you grant. Review before publication: identify the data controller, effective date, applicable law '
        'and the full production processing inventory.'
  ),
  (
    'Information collected',
    'The implemented flows process account details, paired-device information, location and navigation information, '
        'saved places, trip records, support messages and selected display images. '
        'Optional phone and notification features can process caller information and notification content.'
  ),
  (
    'Account information',
    'Registration sends your name, email, phone number and password to the account API. Login sends your credentials; '
        'Google sign-in sends a Google authentication token to the backend. The app stores its session token and cached user profile '
        'in SharedPreferences on the phone. Review before publication: confirm server-side credential handling and account record retention.'
  ),
  (
    'Device and Bluetooth information',
    'Pairing sends a Bluetooth address, device name and, when available, device identifier and version to the backend. '
        'Paired-device information and the Bluetooth address are cached locally for reconnection. '
        'The app reads device state and transfers navigation, display settings, selected images and firmware to the paired device.'
  ),
  (
    'Location and navigation',
    'Location access supports route planning and turn-by-turn guidance. Background location is configured to keep navigation '
        'working while riding. Search and routing requests can send search text, coordinates, origins and destinations to external map services. '
        'Navigation information is also sent to the paired display. Active-session data is saved locally to support resuming navigation.'
  ),
  (
    'Ride history and usage',
    'The application reads trip history and ride statistics from backend APIs and tracks the active ride, including distance, '
        'speed and duration. It sends saved-place labels, addresses and coordinates when you save a place. '
        'Review before publication: confirm which ride samples are persisted by production services and whether server logs or analytics '
        'collect additional usage information. No dedicated analytics SDK was identified in the client dependency list.'
  ),
  (
    'How information is used',
    'The implemented flows use data to authenticate accounts, manage profiles and paired devices, provide navigation, '
        'restore sessions, show history and statistics, customize the display and process support requests. '
        'Support tickets and replies send the content you enter to the backend. Selected display images can be uploaded to the backend '
        'and transferred to the device. Review before publication: confirm purposes and legal bases for all production processing.'
  ),
  (
    'Storage and retention',
    'The client uses local SharedPreferences for session, profile, pairing and navigation-resume information, '
        'and backend APIs for account and feature records. Logout removes authentication and navigation-resume keys; '
        'it does not establish deletion of all local or server records. '
        'Review before publication: confirm hosting locations, storage providers, retention periods, backups and deletion schedules.'
  ),
  (
    'Permissions and controls',
    'You can manage location, Bluetooth, notifications, phone permissions and notification access in phone settings. '
        'Revoking permissions may disable related features. Image selection uses the system image picker. '
        'With Android notification access, notification titles and text can be forwarded to the paired display. '
        'Phone permissions support incoming-call state, caller-number display and answering or rejecting calls. '
        'Review before publication: confirm platform-specific permission behavior and any voice-input processing.'
  ),
  (
    'Third-party services and sharing',
    'The code integrates Google sign-in and Google Maps services. Google Fonts may fetch font files at runtime. '
        'Map search, geocoding and routing include fallback requests '
        'to Photon (Komoot), OpenStreetMap Nominatim and the OSRM routing service. These requests can include query text or coordinates. '
        'Shared map links may be resolved through their hosting services. The image-upload path is documented as using Cloudinary through '
        'the backend; confirm the production provider. Data required for connected features is sent over Bluetooth to the paired device. '
        'Review before publication: confirm all processors, their terms, transfer locations and any other backend disclosures.'
  ),
  (
    'Data security',
    'The configured account API uses an HTTPS URL. The client uses SharedPreferences for cached tokens and records. '
        'This does not establish encryption at rest, end-to-end encryption or a guarantee against unauthorized access. '
        'Protect your phone and credentials. Review before publication: verify backend access controls, storage protection, '
        'logging practices and incident-response procedures.'
  ),
  (
    'Privacy rights',
    'The app provides profile editing, saved-place removal and an account-deletion request. '
        'Other rights and their conditions depend on applicable law. '
        'Review before publication: confirm access, correction, export, objection and complaint procedures, '
        'identity verification and response timeframes.'
  ),
  (
    'Deletion requests',
    'Use Profile > Delete Account to send an authenticated deletion request. On success, the client clears its authentication data. '
        'This does not verify deletion of all server records, uploaded images, backups or third-party records. '
        'Use Help & Support for questions. Review before publication: confirm deletion scope, exceptions, timing '
        'and a verified request channel for users without account access.'
  ),
  (
    'Policy changes',
    'This policy should be reviewed when data flows, permissions or providers change. '
        'Review before publication: approve a change-notification process and effective date; no date is asserted in this draft.'
  ),
  (
    'Contact information',
    'In-app support is available through Profile > Help & Support. '
        'Review before publication: supply the verified controller identity, postal address, privacy contact and '
        'any required data-protection or supervisory-authority contact information.'
  ),
];
