class StoreOffer {
  final String id;
  final String productId;
  final String title;
  final String? subtitle;
  final double regularPricePerUnit;
  final double offerPricePerUnit;
  final DateTime? endsAt;
  final String productName;
  final String? imageUrl;

  const StoreOffer({
    required this.id,
    required this.productId,
    required this.title,
    this.subtitle,
    required this.regularPricePerUnit,
    required this.offerPricePerUnit,
    this.endsAt,
    required this.productName,
    this.imageUrl,
  });

  int get discountPercent {
    if (regularPricePerUnit <= 0) return 0;
    return ((1 - (offerPricePerUnit / regularPricePerUnit)) * 100).round();
  }

  factory StoreOffer.fromMap(Map<String, dynamic> map) {
    final rawProduct = map['products'];
    final product = rawProduct is Map
        ? Map<String, dynamic>.from(rawProduct)
        : <String, dynamic>{};

    return StoreOffer(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      title: map['title']?.toString().trim().isNotEmpty == true
          ? map['title'].toString().trim()
          : 'عرض خاص',
      subtitle: map['subtitle']?.toString(),
      regularPricePerUnit:
          (map['regular_price_per_unit'] as num?)?.toDouble() ?? 0,
      offerPricePerUnit: (map['offer_price_per_unit'] as num?)?.toDouble() ?? 0,
      endsAt: DateTime.tryParse(map['ends_at']?.toString() ?? ''),
      productName: product['name']?.toString() ?? '',
      imageUrl: product['image_url']?.toString(),
    );
  }
}
