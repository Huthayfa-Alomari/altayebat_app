import 'package:supabase_flutter/supabase_flutter.dart';

class ReverseGeocodeResult {
  final String? displayName;
  final String? city;
  final String? area;
  final String? street;
  final String? building;
  final String? postcode;

  const ReverseGeocodeResult({
    this.displayName,
    this.city,
    this.area,
    this.street,
    this.building,
    this.postcode,
  });

  factory ReverseGeocodeResult.fromMap(Map<String, dynamic> map) {
    String? clean(dynamic value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return ReverseGeocodeResult(
      displayName: clean(map['display_name']),
      city: clean(map['city']),
      area: clean(map['area']),
      street: clean(map['street']),
      building: clean(map['building']),
      postcode: clean(map['postcode']),
    );
  }
}

class RouteEtaResult {
  final double distanceKm;
  final int durationMinutes;
  final String provider;

  const RouteEtaResult({
    required this.distanceKm,
    required this.durationMinutes,
    required this.provider,
  });

  factory RouteEtaResult.fromMap(Map<String, dynamic> map) {
    return RouteEtaResult(
      distanceKm: (map['distance_km'] as num?)?.toDouble() ?? 0,
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 0,
      provider: map['provider']?.toString() ?? 'unknown',
    );
  }
}

class LocationIntelligenceService {
  LocationIntelligenceService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<ReverseGeocodeResult?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'reverse-geocode',
        body: {'lat': latitude, 'lng': longitude},
      );
      if (response.status < 200 ||
          response.status >= 300 ||
          response.data is! Map) {
        return null;
      }
      return ReverseGeocodeResult.fromMap(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<RouteEtaResult?> routeEta({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'route-eta',
        body: {
          'from_lat': fromLatitude,
          'from_lng': fromLongitude,
          'to_lat': toLatitude,
          'to_lng': toLongitude,
        },
      );
      if (response.status < 200 ||
          response.status >= 300 ||
          response.data is! Map) {
        return null;
      }
      return RouteEtaResult.fromMap(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      return null;
    }
  }
}
