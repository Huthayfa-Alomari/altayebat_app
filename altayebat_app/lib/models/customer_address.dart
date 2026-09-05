class CustomerAddress {
  final String id;
  final String? label;
  final String? addressText;
  final String? city;
  final String? area;
  final String? street;
  final String? building;
  final String? floor;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? locationSource;
  final bool isDefault;

  const CustomerAddress({
    required this.id,
    this.label,
    this.addressText,
    this.city,
    this.area,
    this.street,
    this.building,
    this.floor,
    this.notes,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.locationSource,
    this.isDefault = false,
  });

  factory CustomerAddress.fromMap(Map<String, dynamic> map) {
    double? toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    return CustomerAddress(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString(),
      addressText: map['address_text']?.toString(),
      city: map['city']?.toString(),
      area: map['area']?.toString(),
      street: map['street']?.toString(),
      building: map['building']?.toString(),
      floor: map['floor']?.toString(),
      notes: map['notes']?.toString(),
      latitude: toDouble(map['lat']),
      longitude: toDouble(map['lng']),
      accuracyMeters: toDouble(map['location_accuracy_m']),
      locationSource: map['location_source']?.toString(),
      isDefault: map['is_default'] == true,
    );
  }

  String get title {
    final value = label?.trim();
    if (value != null && value.isNotEmpty) return value;
    return 'عنوان التوصيل';
  }

  String get compactAddress {
    final explicit = addressText?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final parts = <String>[
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
      if ((area ?? '').trim().isNotEmpty) area!.trim(),
      if ((street ?? '').trim().isNotEmpty) street!.trim(),
      if ((building ?? '').trim().isNotEmpty) 'بناية ${building!.trim()}',
      if ((floor ?? '').trim().isNotEmpty) 'طابق ${floor!.trim()}',
    ];
    return parts.isEmpty ? 'لم تتم إضافة تفاصيل العنوان' : parts.join('، ');
  }

  bool get hasCoordinates => latitude != null && longitude != null;
}
