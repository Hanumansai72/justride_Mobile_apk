# JustRide UI cleanup delivery

## Scope and assets

- Login: removed the remote biker placeholder and its gradient. Retained the logo, form, password visibility, remember-me control, password reset, Google sign-in and signup. Added narrow-screen wrapping and keyboard scroll support without changing authentication logic.
- Device: replaced the painted rectangular mockup with the existing `assets/justride-device.webp`. This is the circular product with silver bezel, black housing, left green button and original green-route navigation screen. It uses `BoxFit.contain`, a constrained width and an accessible description. Removed Device Shortcuts; settings, customization, health, polling and connection actions remain.
- About: uses `assets/justride-logo-horizontal.png`, rasterized at 4x from the user-confirmed `C:/Hanumansai_Projects/Justride/branding/justride-logo-horizontal.svg`. No new logo design or Flutter text wordmark was introduced. The SVG's existing font-based lettering was rendered as provided. The source SVG is unchanged.
- About retains the existing version and update functionality. Removed the motorcycle placeholder, old copyright footer, decorative operational-status animation and Open Source Licenses shortcut.
- Terms & Conditions and Privacy Policy are separate named routes using one themed scrollable screen. Each includes a visible draft notice and inline review items. The normal back action returns to About.
- Flutter's dependency license registry is accessible through Help & Support > Third-party notices. Dependency license files and required map-provider attribution code were not removed.

## Files changed by this task

Created:

- `assets/justride-logo-horizontal.png`
- `lib/features/profile/screens/legal_screen.dart`
- `test/ui_cleanup_test.dart`
- `UI_CLEANUP_REVIEW.md`

Modified:

- `pubspec.yaml` (logo asset registration; no dependency additions)
- `lib/core/routes/app_routes.dart`
- `lib/features/auth/screens/login_screen.dart`
- `lib/features/auth/widgets/login_form.dart` (responsive layout only)
- `lib/features/auth/widgets/social_login_button.dart` (responsive label only)
- `lib/features/device/screens/device_screen.dart`
- `lib/features/device/widgets/device_info_card.dart`
- `lib/features/profile/screens/about_screen.dart`
- `lib/features/profile/screens/help_support_screen.dart`

Removed:

- `lib/features/device/widgets/device_shortcuts.dart` (no other callers found)

Many files were already modified before this task. Their existing work was preserved; Git's overall diff includes those prior changes.

## Privacy evidence reviewed

| Client evidence | Policy coverage |
| --- | --- |
| Android manifest and iOS Info.plist | Location/background location, Bluetooth, phone, notifications, image-picker-related platform behavior |
| `pubspec.yaml`, Google auth service, backend service | SDK inventory; registration fields; Google token exchange; support tickets; pairing; saved places; image upload; account deletion |
| API client and navigation service | SharedPreferences session/profile/pairing/resume data; HTTPS API configuration; logout/deletion client cleanup |
| Google Maps service | Google APIs; Photon, Nominatim and OSRM fallback requests including search text and coordinates |
| Telephony and notification-listener services; BLE navigation service | Caller-number/call-state processing and notification-title/text forwarding to the paired display |
| Trips models/screens and backend service | History and statistics read paths; no assumption that every location sample is retained |

The drafts describe client-observed behavior. They are not certification of production backend or third-party processing. In particular, the client dependency list contains no dedicated analytics SDK, but that does not establish absence of server analytics. Google Fonts can fetch typography at runtime; this should be included in the final production provider inventory.

## Legal items requiring confirmation before publication

- Operator/controller identity, legal entity, postal address, verified legal/privacy contact and contact without login.
- Effective date, jurisdiction, eligibility/age rules, acceptance and change-notice process.
- Intellectual-property ownership and license terms; suspension/termination procedures; legally permitted warranties and liability wording.
- Production providers and processors, international transfers, hosting locations, purposes and legal bases.
- Retention periods, backups, deletion scope and timing, credential/storage protection, access controls, logs and incident response.
- Privacy-rights handling, identity verification, response timelines and complaint process.
- Platform-specific permissions and voice-input processing.

## Validation

Results: all 91 tests passed; the final focused run passed all 4 UI checks; targeted analysis of every changed Dart file found no issues. The Android debug APK built successfully at `build/app/outputs/flutter-apk/app-debug.apk`. Both bundled branding images were read from the APK and matched their source bytes. The build emitted non-fatal Java native-access and Android SDK XML-version warnings.

The focused widget checks cover About legal links, full scrolling and back navigation at 320x640 and 430x932, removed About items, login validation with a 300px keyboard inset, and the device product asset plus connection controls at 320px width.

Commands used:

```text
dart analyze <all changed Dart files and test/ui_cleanup_test.dart>
flutter test --no-pub
flutter build apk --debug --no-pub
```

Live account credentials, Google authorization, physical Bluetooth hardware and a phone were not supplied. Live sign-in, physical pairing/reconnection and road navigation therefore still require device acceptance testing. Experimental widget screenshots used the test renderer's fallback font and are not product previews.
