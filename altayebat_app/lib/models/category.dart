class ProductCategory {
  final String id;
  final String name;
  final int sortOrder;
  final String? imageUrl;
  final String? parentId;

  ProductCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.imageUrl,
    this.parentId,
  });

  bool get isRoot => parentId == null;

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id'] as String,
      name: map['name'] as String,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      imageUrl: map['image_url']?.toString(),
      parentId: map['parent_id']?.toString(),
    );
  }
}
