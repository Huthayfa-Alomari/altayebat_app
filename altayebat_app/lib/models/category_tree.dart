import 'category.dart';

class CategoryTree {
  final List<ProductCategory> categories;
  late final Map<String, ProductCategory> byId = {
    for (final c in categories) c.id: c,
  };
  CategoryTree(this.categories);
  List<ProductCategory> get roots => categories
      .where((c) => c.parentId == null || !byId.containsKey(c.parentId))
      .toList();
  List<ProductCategory> childrenOf(String id) =>
      categories.where((c) => c.parentId == id && c.id != id).toList();
  List<ProductCategory> pathTo(ProductCategory category) {
    final path = <ProductCategory>[];
    final visited = <String>{};
    ProductCategory? current = byId[category.id] ?? category;
    while (current != null && visited.add(current.id)) {
      path.add(current);
      current = byId[current.parentId];
    }
    return path.reversed.toList();
  }

  ProductCategory rootOf(ProductCategory category) => pathTo(category).first;
  List<ProductCategory> descendantsOf(String id) {
    final visited = <String>{id};
    final result = <ProductCategory>[];
    void append(String parent) {
      for (final child in childrenOf(parent)) {
        if (visited.add(child.id)) {
          result.add(child);
          append(child.id);
        }
      }
    }

    append(id);
    return result;
  }
}
