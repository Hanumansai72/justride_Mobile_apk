# Profile Page Implementation Plan

This plan outlines the steps to design and implement the Profile page for the JustRide app, matching the provided design image.

## User Review Required

> [!IMPORTANT]
> The profile page will be integrated into the existing bottom navigation bar. I will need to update the navigation logic in several screens to ensure consistent behavior when switching to the Profile tab.

## Proposed Changes

### Profile Feature

#### [NEW] [profile_screen.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/profile/screens/profile_screen.dart)
The main screen for the profile, which will host the header, profile card, and menu items in a scrollable view.

#### [NEW] [profile_header.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/profile/widgets/profile_header.dart)
A widget for the "Profile" title, subtitle, and action icons (Notification, Settings).

#### [NEW] [profile_card.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/profile/widgets/profile_card.dart)
A widget for the user's basic info (avatar, name, email, phone) and key stats (Total Trips, Distance, CO₂ Saved).

#### [NEW] [profile_menu_item.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/profile/widgets/profile_menu_item.dart)
A reusable widget for the menu items like "My Devices", "Ride Preferences", etc.

### Navigation & Integration

#### [MODIFY] [app.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/app/app.dart)
Register the `/profile` route.

#### [MODIFY] [dashboard_screen.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/dashboard/screens/dashboard_screen.dart)
#### [MODIFY] [trips_screen.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/trips/screens/trips_screen.dart)
#### [MODIFY] [device_screen.dart](file:///C:/Hanumansai_Projects/MobileApp-main/MobileApp-main/lib/features/device/screens/device_screen.dart)
Update the `JustRideBottomNavBar` tap logic to navigate to the Profile screen.

## Verification Plan

### Manual Verification
- Verify the layout of the Profile page matches the design image.
- Test navigation to and from the Profile page using the bottom navigation bar.
- Ensure the "Log Out" button and menu items look as expected.
