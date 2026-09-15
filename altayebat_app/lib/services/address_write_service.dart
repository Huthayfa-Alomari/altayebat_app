import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_address.dart';

class AddressWriteService {
  AddressWriteService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('يجب تسجيل الدخول قبل حفظ العنوان');
    return userId;
  }

  static String? _clean(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _addressText({
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
  }) {
    final parts = <String>[
      city.trim(),
      area.trim(),
      if ((street ?? '').trim().isNotEmpty) street!.trim(),
      if ((building ?? '').trim().isNotEmpty) 'بناية ${building!.trim()}',
      if ((floor ?? '').trim().isNotEmpty) 'طابق ${floor!.trim()}',
      if ((apartment ?? '').trim().isNotEmpty) 'شقة ${apartment!.trim()}',
      if ((landmark ?? '').trim().isNotEmpty) 'قرب ${landmark!.trim()}',
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.join('، ');
  }

  static Map<String, dynamic> _payload({
    required String label,
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? recipientName,
    String? recipientPhone,
    String? notes,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String locationSource = 'manual',
  }) {
    return <String, dynamic>{
      'label': _clean(label),
      'city': _clean(city),
      'area': _clean(area),
      'street': _clean(street),
      'building': _clean(building),
      'floor': _clean(floor),
      'apartment': _clean(apartment),
      'landmark': _clean(landmark),
      'recipient_name': _clean(recipientName),
      'recipient_phone': _clean(recipientPhone),
      'notes': _clean(notes),
      'lat': latitude,
      'lng': longitude,
      'location_accuracy_m': accuracyMeters,
      'location_source': _clean(locationSource),
      'address_text': _addressText(
        city: city,
        area: area,
        street: street,
        building: building,
        floor: floor,
        apartment: apartment,
        landmark: landmark,
      ),
    };
  }

  static Future<CustomerAddress> create({
    required String label,
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? recipientName,
    String? recipientPhone,
    String? notes,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String locationSource = 'manual',
    bool isDefault = false,
  }) async {
    final payload =
        _payload(
            label: label,
            city: city,
            area: area,
            street: street,
            building: building,
            floor: floor,
            apartment: apartment,
            landmark: landmark,
            recipientName: recipientName,
            recipientPhone: recipientPhone,
            notes: notes,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracyMeters,
            locationSource: locationSource,
          )
          ..['customer_id'] = _requireUserId()
          ..['is_default'] = isDefault;

    final row = await _client
        .from('addresses')
        .insert(payload)
        .select()
        .single();
    return CustomerAddress.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<CustomerAddress> update({
    required String addressId,
    required String label,
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? recipientName,
    String? recipientPhone,
    String? notes,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String locationSource = 'manual',
  }) async {
    final userId = _requireUserId();
    final payload = _payload(
      label: label,
      city: city,
      area: area,
      street: street,
      building: building,
      floor: floor,
      apartment: apartment,
      landmark: landmark,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      notes: notes,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      locationSource: locationSource,
    )..['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final row = await _client
        .from('addresses')
        .update(payload)
        .eq('id', addressId)
        .eq('customer_id', userId)
        .select()
        .single();
    return CustomerAddress.fromMap(Map<String, dynamic>.from(row));
  }
}
