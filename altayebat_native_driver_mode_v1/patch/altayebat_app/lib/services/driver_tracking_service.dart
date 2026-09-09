import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverTrackingService {
  DriverTrackingService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw StateError('Unexpected RPC response');
  }

  static Future<Map<String, dynamic>> bootstrap(String token) async {
    final value = await _db.rpc(
      'driver_tracking_bootstrap',
      params: {'p_token': token},
    );
    return _asMap(value);
  }

  static Future<Map<String, dynamic>> startDelivery(
    String token,
    Position position,
  ) async {
    final value = await _db.rpc(
      'driver_tracking_start_delivery',
      params: {
        'p_token': token,
        'p_lat': position.latitude,
        'p_lng': position.longitude,
        'p_accuracy_m': _validNonNegative(position.accuracy),
      },
    );
    return _asMap(value);
  }

  static Future<Map<String, dynamic>> pushLocation(
    String token,
    Position position,
  ) async {
    final value = await _db.rpc(
      'driver_tracking_push_location',
      params: {
        'p_token': token,
        'p_lat': position.latitude,
        'p_lng': position.longitude,
        'p_accuracy_m': _validNonNegative(position.accuracy),
        'p_speed_mps': _validSpeed(position.speed),
        'p_heading_deg': _validHeading(position.heading),
      },
    );
    return _asMap(value);
  }

  static Future<Map<String, dynamic>> completeDelivery(String token) async {
    final value = await _db.rpc(
      'driver_tracking_complete_delivery',
      params: {'p_token': token},
    );
    return _asMap(value);
  }

  static double? _validNonNegative(double value) {
    if (!value.isFinite || value < 0) return null;
    return value;
  }

  static double? _validSpeed(double value) {
    if (!value.isFinite || value < 0 || value > 120) return null;
    return value;
  }

  static double? _validHeading(double value) {
    if (!value.isFinite || value < 0 || value >= 360) return null;
    return value;
  }
}
