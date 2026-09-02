/// Data model representing a single completed trip.
class TripModel {
  const TripModel({
    required this.origin,
    required this.destination,
    required this.dateLabel,
    required this.distanceKm,
    required this.durationMin,
    required this.co2SavedKg,
  });

  final String origin;
  final String destination;
  final String dateLabel;
  final double distanceKm;
  final int durationMin;
  final double co2SavedKg;

  // ── Static dummy data ──────────────────────────────────────────────────────
  static const List<TripModel> dummyTrips = [
    TripModel(
      origin: 'HITEC City, Hyderabad',
      destination: 'Gachibowli, Hyderabad',
      dateLabel: 'Today, 9:15 AM',
      distanceKm: 12.4,
      durationMin: 25,
      co2SavedKg: 2.1,
    ),
    TripModel(
      origin: 'Home',
      destination: 'Work',
      dateLabel: 'Yesterday, 8:20 AM',
      distanceKm: 18.7,
      durationMin: 34,
      co2SavedKg: 3.2,
    ),
    TripModel(
      origin: 'Charminar, Hyderabad',
      destination: 'Secunderabad',
      dateLabel: '25 May, 7:40 PM',
      distanceKm: 8.3,
      durationMin: 20,
      co2SavedKg: 1.4,
    ),
    TripModel(
      origin: 'Raidurg Metro Station',
      destination: 'Home',
      dateLabel: '24 May, 6:30 PM',
      distanceKm: 15.2,
      durationMin: 28,
      co2SavedKg: 2.6,
    ),
  ];
}
