class Product {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final int stockQty;
  final bool isAvailable;
  final String? categoryId;

  Product({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.stockQty,
    required this.isAvailable,
    this.categoryId,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      stockQty: (map['stock_qty'] as num?)?.toInt() ?? 0,
      isAvailable: map['is_available'] as bool? ?? true,
      categoryId: map['category_id'] as String?,
    );
  }
}