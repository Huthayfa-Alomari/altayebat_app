import 'package:flutter_test/flutter_test.dart';
import 'package:altayebat_app/models/product.dart';
import 'package:altayebat_app/providers/cart_provider.dart';

Product product({
  String id = 'product-1',
  int stock = 2,
  bool available = true,
  double price = 1.5,
}) {
  return Product(
    id: id,
    name: 'منتج',
    price: price,
    stockQty: stock,
    isAvailable: available,
  );
}

void main() {
  group('CartProvider', () {
    test('adds items and calculates total', () {
      final cart = CartProvider();
      final item = product(price: 2.25);

      expect(cart.add(item), isTrue);
      expect(cart.add(item), isTrue);

      expect(cart.itemCount, 2);
      expect(cart.quantityOf(item.id), 2);
      expect(cart.total, 4.5);
    });

    test('does not exceed available stock', () {
      final cart = CartProvider();
      final item = product(stock: 1);

      expect(cart.add(item), isTrue);
      expect(cart.add(item), isFalse);
      expect(cart.quantityOf(item.id), 1);
      expect(cart.canAdd(item), isFalse);
    });

    test('does not add unavailable products', () {
      final cart = CartProvider();
      final unavailable = product(available: false, stock: 5);
      final noStock = product(id: 'product-2', stock: 0);

      expect(cart.add(unavailable), isFalse);
      expect(cart.add(noStock), isFalse);
      expect(cart.isEmpty, isTrue);
    });

    test('decrement removes item when quantity reaches zero', () {
      final cart = CartProvider();
      final item = product();

      cart.add(item);
      cart.decrement(item);

      expect(cart.isEmpty, isTrue);
      expect(cart.itemCount, 0);
    });
  });
}
