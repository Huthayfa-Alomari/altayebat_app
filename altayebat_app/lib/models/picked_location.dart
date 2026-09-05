class PickedLocation {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String source;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.source = 'map',
  });
}
