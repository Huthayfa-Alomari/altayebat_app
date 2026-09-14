class Product {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final int stockQty;
  final bool isAvailable;
  final String? categoryId;
  final String saleType;
  final String baseUnit;
  final int inventoryScale;
  final double pricePerUnit;
  final int minQty;
  final int qtyStep;
  final bool allowAmountPurchase;

  Product({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.stockQty,
    required this.isAvailable,
    this.categoryId,
    this.saleType = 'piece',
    this.baseUnit = 'piece',
    this.inventoryScale = 1,
    double? pricePerUnit,
    this.minQty = 1,
    this.qtyStep = 1,
    this.allowAmountPurchase = false,
  }) : pricePerUnit = pricePerUnit ?? price;

  factory Product.fromMap(Map<String, dynamic> map) {
    final price = (map['price'] as num).toDouble();
    final inventoryScale = (map['inventory_scale'] as num?)?.toInt() ?? 1;
    final explicitDisplayPrice = (map['price_per_unit'] as num?)?.toDouble();

    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: price,
      imageUrl: map['image_url'] as String?,
      stockQty: (map['stock_qty'] as num?)?.toInt() ?? 0,
      isAvailable: map['is_available'] as bool? ?? true,
      categoryId: map['category_id'] as String?,
      saleType: map['sale_type']?.toString() ?? 'piece',
      baseUnit: map['base_unit']?.toString() ?? 'piece',
      inventoryScale: inventoryScale > 0 ? inventoryScale : 1,
      pricePerUnit:
          explicitDisplayPrice ?? price * (inventoryScale > 0 ? inventoryScale : 1),
      minQty: ((map['min_qty'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
      qtyStep: ((map['qty_step'] as num?)?.toInt() ?? 1).clamp(1, 1 << 30),
      allowAmountPurchase: map['allow_amount_purchase'] as bool? ?? false,
    );
  }

  bool get isMeasured =>
      saleType == 'weight' || allowAmountPurchase || inventoryScale > 1;

  int get initialCartQuantity => minQty > 0 ? minQty : 1;

  int get cartStep => qtyStep > 0 ? qtyStep : 1;

  double get displayPrice => isMeasured ? pricePerUnit : price;

  String get displayUnitLabel {
    switch (baseUnit.toLowerCase()) {
      case 'kg':
        return 'كغم';
      case 'g':
        return 'غ';
      case 'l':
      case 'liter':
      case 'litre':
        return 'لتر';
      case 'ml':
        return 'مل';
      default:
        return 'قطعة';
    }
  }

  String get priceDisplayText => isMeasured
      ? '${displayPrice.toStringAsFixed(2)} د.أ / $displayUnitLabel'
      : '${displayPrice.toStringAsFixed(2)} د.أ';

  String formatQuantity(int quantity) {
    if (!isMeasured || inventoryScale <= 1) return '$quantity';

    final normalizedBaseUnit = baseUnit.toLowerCase();
    if (normalizedBaseUnit == 'kg' && inventoryScale == 1000) {
      if (quantity < 1000) return '$quantity غ';
      return '${_trimDecimal(quantity / 1000)} كغم';
    }

    if ((normalizedBaseUnit == 'l' ||
            normalizedBaseUnit == 'liter' ||
            normalizedBaseUnit == 'litre') &&
        inventoryScale == 1000) {
      if (quantity < 1000) return '$quantity مل';
      return '${_trimDecimal(quantity / 1000)} لتر';
    }

    return '${_trimDecimal(quantity / inventoryScale)} $displayUnitLabel';
  }

  String get stockDisplayText => formatQuantity(stockQty);

  bool get isLowStock {
    if (stockQty <= 0) return false;
    if (isMeasured) return stockQty < initialCartQuantity + (cartStep * 3);
    return stockQty <= 3;
  }

  static String _trimDecimal(double value) {
    var text = value.toStringAsFixed(3);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }
}
