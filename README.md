# JustRide Mobile App (justride_Mobile_apk)

Production Flutter mobile application for the JustRide motorcycle IoT navigation ecosystem.

## Features
- **Turn-by-Turn Navigation**: Real-time motorcycle route planning with Google Routes API v2 & OSRM fallback.
- **ESP32 BLE HUD Sync**: Real-time packet streaming (maneuvers, speed, distance, time, clock) to ESP32-S3 TFT display.
- **Go Screen (`/go`)**: Instant Start/Endpoint route planner with location-biased transit suggestions.
- **Voice Assistant**: Integrated voice prompt & quick transit destination suggestions.
- **Google Sign-In**: Native Google OAuth authentication.
- **Live Device Status**: Live Bluetooth sync for battery, signal, and connection state.

## Version
- **Version**: `v1.2.0+3`
- **SDK**: Flutter `>=3.3.0 <4.0.0`
