import 'package:flutter_test/flutter_test.dart';
import 'package:altayebat_app/models/product.dart';

void main() {
  group('Product', () {
    test('parses Supabase row safely', () {
      final product = Product.fromMap({
        'id': 'product-1',
        'name': 'حليب طازج',
        'description': '1 لتر',
        'price': 1.25,
        'image_url': null,
        'stock_qty': 8,
        'is_available': true,
        'category_id': 'dairy',
      });

      expect(product.id, 'product-1');
      expect(product.name, 'حليب طازج');
      expect(product.price, 1.25);
      expect(product.stockQty, 8);
      expect(product.isAvailable, isTrue);
      expect(product.categoryId, 'dairy');
    });

    test('uses safe defaults for optional inventory fields', () {
      final product = Product.fromMap({
        'id': 'product-2',
        'name': 'مياه',
        'price': 0.35,
      });

      expect(product.stockQty, 0);
      expect(product.isAvailable, isTrue);
      expect(product.description, isNull);
      expect(product.imageUrl, isNull);
      expect(product.categoryId, isNull);
    });
  });
}
