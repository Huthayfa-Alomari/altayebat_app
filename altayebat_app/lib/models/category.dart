class ProductCategory {
  final String id;
  final String name;
  final int sortOrder;

  ProductCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id'] as String,
      name: map['name'] as String,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}