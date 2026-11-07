# JustRide Mobile App (justride_Mobile_apk)

Production Flutter mobile application for the JustRide motorcycle IoT navigation ecosystem.

## Features
- **Turn-by-Turn Navigation**: Real-time motorcycle route planning with Google Routes API v2 & OSRM fallback.
- **ESP32 BLE HUD Sync**: Real-time packet streaming (maneuvers, speed, distance, time, clock) to ESP32-S3 TFT display.
- **Go Screen (`/go`)**: Instant Start/Endpoint route planner with location-biased transit suggestions.
- **Voice Assistant**: Integrated voice prompt & quick transit destination suggestions.
- **Google Sign-In**: Native Google OAuth authentication.
- **Live Device Status**: Live Bluetooth sync for battery, signal, and connection state.

## Ride history

Navigation saves a summary when the rider arrives or ends the ride. History and the home screen's latest ride read the signed-in user's records from `/api/rides`, newest first, with 10 rides per history page. Sample trips, streaks and estimated environmental statistics are not displayed as real history.

Uploads are persisted in a per-user SharedPreferences queue before sending. Failed uploads retry when home/history refreshes; the backend uses a unique session ID per user to avoid duplicates. Account changes cannot upload one user's pending summaries under another account. A successful upload refreshes open history/home views. The backend ride endpoints must be deployed before this works against `backend.justride.cc`; older debug-only summaries cannot be recovered.

## App version
- **Version**: `v1.2.0+3`
- **SDK**: Flutter `>=3.3.0 <4.0.0`

## Account deletion

Profile and Profile Settings open the same deletion flow. Linked devices must be released using an email unlink code first. The user then requests a separate account deletion OTP, enters their current password for a local account, and confirms permanent deletion. Device Settings also supports verified unlinking.

Deletion removes profile content, rides, saved places and support records; the backend retains an email/phone reservation to prevent reuse. The UI explains this before confirmation. Successful deletion clears the local session, device pairing and pending rides for that user. Failed verification keeps the account signed in. Deploy the backend account-deletion endpoints before installing this version.

Run the isolated flow tests with `flutter test test/account_deletion_test.dart`.

## Help Center

Profile opens a searchable Help Center with 24 bundled troubleshooting articles and categories for Getting started, Connectivity, Navigation, Firmware and Account. Device Settings and Go have contextual help buttons. Answers and guided checklists work offline; feedback and support tickets require internet. Product marketing FAQs are maintained separately in the customer website.

The support form sends a real ticket to `/api/support/tickets`, with its category, description, optional article reference and up to three screenshots (5 MB each). Screenshot selection is local; upload starts only when the user sends the ticket after agreeing to share. Cloudinary screenshot URLs are accessible to anyone with the link, so remove private details first. The app preserves the draft on failed submission. My Tickets shows backend status and replies; pull to refresh or use Refresh in a thread.

Diagnostics are optional. The checkbox enables app/platform version, a labelled cached firmware version, Android phone/OS information where available, and an optional error code. Users can preview or copy the report. GPS, passwords, OTPs, notification contents and account/device credentials are excluded. Feedback is saved per user/article and is visible in admin Support Management > Help feedback.

Run `flutter test test/help_center_test.dart` for offline search, compact layout, support handoff, feedback retry, draft preservation, backend replies, diagnostic fields and screenshot MIME checks. Deploy the matching backend first; configure Cloudinary in that environment. Keep `assets/help/app_faqs.json` IDs/questions aligned with the backend catalog.

## Browser app

The same Flutter app runs on the web, with a centered phone-width layout on desktop and the existing emerald theme. It uses `https://backend.justride.cc/api`; it is separate from the customer landing page.

```sh
flutter run -d chrome --web-port 3100
flutter build web --release --dart-define=GOOGLE_MAPS_API_KEY=YOUR_BROWSER_RESTRICTED_KEY
```

Serve the generated `build/web` directory on localhost for preview or HTTPS for deployment. Routes use Flutter's default hash URLs. Allow the web app origin in backend CORS before deploying to a new domain.

- Email/password authentication uses the existing backend. Google sign-in also requires this browser origin in the Google OAuth client's authorized JavaScript origins.
- Maps require a browser-restricted Google Maps JavaScript API key supplied with the dart define above; Android's native key is not reused automatically. Without a key, the app still opens and the navigation screen reports the map as unavailable. Google routing/Places API access must also permit the web origin.
- Location requires browser permission and HTTPS (localhost is allowed). Bluetooth requires a supported Chrome/Edge browser, a secure context, and clicking **Choose device** on the pairing screen; there is no automatic browser scan. Device MAC identity and Android-specific pairing flows may differ in browsers and need hardware verification.
- Native Android sharing intents, phone-call monitoring, and system notification access do not initialize on web. These remain APK features.

## Android device power-on reconnect

On Android 12+, sign in and pair the device once, grant Nearby devices permission,
and approve Android's companion-device dialog. For an existing pairing, enable
**Device Settings > Connect when device powers on**. Setup briefly releases an
existing Bluetooth connection so Android can find the advertising device, then
reconnects. Keep the device on during approval.

Android's CompanionDeviceService observes the approved device and wakes the app's
shared Flutter engine when it appears. The existing Bluetooth service remains the
only GATT owner; opening the app reuses that engine and connection. Background
wakeup does not open a screen, continuously scan, or start a saved ride. Media
commands use application context so they also work without an Activity.

Manual Disconnect pauses reconnect until a manual connection is requested.
Unlinking, logout, account deletion and session expiry disable presence observation
and remove the Android association. Boot, app update and Bluetooth-on broadcasts
restore observation for the saved association.

Bluetooth and Nearby devices permission must remain enabled. Android force-stop
prevents background wakeup until the app is opened again; manufacturer battery
restrictions may also affect delivery. Android versions below 12 and web retain
their existing foreground Bluetooth behavior.

Verification: release APK compiled; a temporary mocked-channel check covered
headless initialization, authentication, manual-disconnect suppression, concurrent
presence events sharing one connect attempt, unlink cleanup, and foreground UI
handoff. The temporary check was removed. No Android phone was attached: validate
approval, power-cycle reconnect with the app closed, Home/app switching, reboot,
and unlink/logout on a real phone before release.

Platform reference: https://developer.android.com/develop/connectivity/bluetooth/ble/background


## Device road maps (Google Static Maps)

The device uses `/api/maps/google-static` for Google road imagery, with Google
route/navigation packets restored. Phone Google navigation is unchanged.
`GOOGLE_DEVICE_MAPS` defaults to false for the route-focused HUD; Google imagery is opt-in.
The backend needs `GOOGLE_MAPS_STATIC_API_KEY` with Maps Static API enabled and
active billing, and the production Redis quota store. Images are 226x177; the
provider attribution strip is preserved. The earlier live Google request was
rejected because billing was not enabled. OSM device roads have been removed.
The later touch/music alignment, sensor and clock fixes are retained.

## Device media recovery

The engine-owned media channel is also reattached when the Activity configures
the shared engine. Native media calls use a serial background task queue so a
slow player does not block the Flutter/BLE platform thread. Retry (command 7)
reattaches the media channel and requests a notification-listener rebind when
access is already enabled. Missing-channel recovery retries the snapshot once;
play/pause/skip commands are never replayed automatically.

Native reads and commands time out after three seconds. A rejected command does
not replace a healthy snapshot with state 7. Missing access remains state 1 and
no active player remains state 2. Native failures log the method and exception
type; Dart logs the channel error code. MODIFY_AUDIO_SETTINGS is declared for
volume control. This change requires an updated APK; firmware is unchanged.

On a phone, enable JustRide notification access, open a music player and start
a track, connect the device and press Retry. Check play/pause/skip/volume, then
switch apps and repeat. Real phone playback verification is still required.

## Current-approach device camera

The default device view frames the current road up to the current maneuver. At
131 m on a straight approach, that road fills the forward map area. Within
60 m, up to 30 m of the current turn's exit is revealed; that exit is capped
before the following maneuver. The camera keeps at least 70 m of context near
the turn and at most 300 m ahead. Real road curves are preserved. Display
geometry updates on a maneuver change or after 3 m of GPS movement.

Static device imagery is opt-in so it cannot replace this follow camera during
a ride. Phone Google navigation and the media recovery fix are retained. Both
the updated APK and firmware are required. Native render checks use sample
routes; physical GPS/BLE road testing is still required.
