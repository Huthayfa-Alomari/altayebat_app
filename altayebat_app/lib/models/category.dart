class ProductCategory {
  final String id;
  final String name;
  final String? nameEn;
  final int sortOrder;
  final String? imageUrl;
  final String? parentId;

  ProductCategory({
    required this.id,
    required this.name,
    this.nameEn,
    required this.sortOrder,
    this.imageUrl,
    this.parentId,
  });

  bool get isRoot => parentId == null;
  String displayName(bool english) =>
      english && (nameEn?.trim().isNotEmpty ?? false) ? nameEn!.trim() : name;

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id'] as String,
      name: map['name'] as String,
      nameEn: map['name_en']?.toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      imageUrl: map['image_url']?.toString(),
      parentId: map['parent_id']?.toString(),
    );
  }
}
