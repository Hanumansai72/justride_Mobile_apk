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
- Native Android sharing intents, phone-call monitoring, and system notification access do not initialize on web. These remain APK features. Simulator sockets use a cross-platform WebSocket channel; an HTTPS deployment needs a secure `wss://` simulator endpoint.
