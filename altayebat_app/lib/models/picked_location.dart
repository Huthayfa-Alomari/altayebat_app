class PickedLocation {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String source;
  final String? displayName;
  final String? city;
  final String? area;
  final String? street;
  final String? building;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.source = 'map',
    this.displayName,
    this.city,
    this.area,
    this.street,
    this.building,
  });
}
