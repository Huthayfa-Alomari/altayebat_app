enum ProductSaleType { piece, weight, volume }

class Product {
  final String id;
  final String name;
  final String? description;

  /// Price of one atomic checkout unit.
  /// piece: 1 piece, weight: 1 gram, volume: 1 millilitre.
  final double price;
  final String? imageUrl;

  /// Stock in atomic units. Kept as an int so the existing checkout/payment
  /// contract remains fully backward compatible.
  final int stockQty;
  final bool isAvailable;
  final String? categoryId;

  final ProductSaleType saleType;
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
    this.saleType = ProductSaleType.piece,
    this.baseUnit = 'piece',
    this.inventoryScale = 1,
    double? pricePerUnit,
    this.minQty = 1,
    this.qtyStep = 1,
    this.allowAmountPurchase = false,
  }) : pricePerUnit = pricePerUnit ?? price;

  bool get isMeasured => saleType != ProductSaleType.piece;
  bool get isWeight => saleType == ProductSaleType.weight;
  bool get isVolume => saleType == ProductSaleType.volume;

  String get unitLabel {
    switch (saleType) {
      case ProductSaleType.weight:
        return 'كغ';
      case ProductSaleType.volume:
        return 'لتر';
      case ProductSaleType.piece:
        return 'قطعة';
    }
  }

  String get smallUnitLabel {
    switch (saleType) {
      case ProductSaleType.weight:
        return 'غ';
      case ProductSaleType.volume:
        return 'مل';
      case ProductSaleType.piece:
        return 'قطعة';
    }
  }

  double get displayStock => stockQty / inventoryScale;

  String get priceLabel => isMeasured
      ? '${pricePerUnit.toStringAsFixed(2)} د.أ / $unitLabel'
      : '${pricePerUnit.toStringAsFixed(2)} د.أ';

  String formatQuantity(int quantity) {
    if (!isMeasured) return '$quantity';

    if (quantity < inventoryScale) {
      return '$quantity $smallUnitLabel';
    }

    final units = quantity / inventoryScale;
    final text = units == units.roundToDouble()
        ? units.toStringAsFixed(0)
        : units.toStringAsFixed(units < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$text $unitLabel';
  }

  String get stockLabel => isMeasured
      ? formatQuantity(stockQty)
      : '$stockQty ${stockQty == 1 ? 'قطعة' : 'قطع'}';

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawSaleType = map['sale_type']?.toString().trim().toLowerCase();
    final saleType = switch (rawSaleType) {
      'weight' => ProductSaleType.weight,
      'volume' => ProductSaleType.volume,
      _ => ProductSaleType.piece,
    };

    final defaultScale = saleType == ProductSaleType.piece ? 1 : 1000;
    final scale = (map['inventory_scale'] as num?)?.toInt() ?? defaultScale;
    final atomicPrice = (map['price'] as num).toDouble();

    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: atomicPrice,
      imageUrl: map['image_url'] as String?,
      stockQty: (map['stock_qty'] as num?)?.toInt() ?? 0,
      isAvailable: map['is_available'] as bool? ?? true,
      categoryId: map['category_id'] as String?,
      saleType: saleType,
      baseUnit: map['base_unit']?.toString() ??
          (saleType == ProductSaleType.weight
              ? 'kg'
              : saleType == ProductSaleType.volume
                  ? 'liter'
                  : 'piece'),
      inventoryScale: scale > 0 ? scale : defaultScale,
      pricePerUnit: (map['price_per_unit'] as num?)?.toDouble() ??
          atomicPrice * (scale > 0 ? scale : defaultScale),
      minQty: (map['min_qty'] as num?)?.toInt() ??
          (saleType == ProductSaleType.piece ? 1 : 100),
      qtyStep: (map['qty_step'] as num?)?.toInt() ??
          (saleType == ProductSaleType.piece ? 1 : 50),
      allowAmountPurchase:
          map['allow_amount_purchase'] as bool? ?? saleType != ProductSaleType.piece,
    );
  }
}
