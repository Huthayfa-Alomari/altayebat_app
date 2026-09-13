import 'package:flutter_test/flutter_test.dart';
import 'package:altayebat_app/models/cart_item.dart';
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

Product measuredProduct({
  String id = 'lentils',
  int stock = 12500,
  double pricePerKg = 1.75,
  int minQty = 100,
  int qtyStep = 50,
}) {
  return Product(
    id: id,
    name: 'عدس أحمر',
    price: pricePerKg / 1000,
    pricePerUnit: pricePerKg,
    stockQty: stock,
    isAvailable: true,
    saleType: ProductSaleType.weight,
    baseUnit: 'kg',
    inventoryScale: 1000,
    minQty: minQty,
    qtyStep: qtyStep,
    allowAmountPurchase: true,
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

    test('measured product uses grams and still counts as one cart line', () {
      final cart = CartProvider();
      final lentils = measuredProduct();

      expect(cart.setQuantity(lentils, 500), isTrue);

      expect(cart.quantityOf(lentils.id), 500);
      expect(cart.itemCount, 1);
      expect(cart.lineCount, 1);
      expect(cart.total, closeTo(0.875, 0.000001));
      expect(cart.itemFor(lentils.id)?.quantityLabel, '500 غ');
    });

    test('measured product preserves by-value request as a UX hint', () {
      final cart = CartProvider();
      final lentils = measuredProduct();

      expect(cart.setQuantity(lentils, 571, requestedAmount: 1.0), isTrue);

      expect(cart.itemFor(lentils.id)?.requestedAmount, 1.0);
      expect(cart.total, closeTo(0.99925, 0.000001));
    });

    test('measured quantity rejects values below minimum or above stock', () {
      final cart = CartProvider();
      final lentils = measuredProduct(stock: 1000, minQty: 100);

      expect(cart.setQuantity(lentils, 50), isFalse);
      expect(cart.setQuantity(lentils, 1001), isFalse);
      expect(cart.isEmpty, isTrue);
    });

    test('regular add button does not treat grams as piece increments', () {
      final cart = CartProvider();
      final lentils = measuredProduct();

      expect(cart.add(lentils), isFalse);
      expect(cart.isEmpty, isTrue);
    });

    test(
      'reorder replacement restores piece and measured quantities at once',
      () {
        final cart = CartProvider();
        final oldItem = product(id: 'old', stock: 3);
        final milk = product(id: 'milk', stock: 6, price: 0.8);
        final lentils = measuredProduct(stock: 5000);

        cart.add(oldItem);
        cart.replaceAll([
          CartItem(product: milk, quantity: 2),
          CartItem(product: lentils, quantity: 500),
        ]);

        expect(cart.quantityOf(oldItem.id), 0);
        expect(cart.quantityOf(milk.id), 2);
        expect(cart.quantityOf(lentils.id), 500);
        expect(cart.lineCount, 2);
        expect(cart.itemCount, 3);
        expect(cart.total, closeTo(2.475, 0.000001));
      },
    );
  });

  group('Product measured formatting', () {
    test('parses measured metadata returned by Supabase', () {
      final parsed = Product.fromMap({
        'id': 'lentils',
        'name': 'عدس أحمر',
        'price': 0.00175,
        'price_per_unit': 1.75,
        'stock_qty': 12500,
        'is_available': true,
        'sale_type': 'weight',
        'base_unit': 'kg',
        'inventory_scale': 1000,
        'min_qty': 100,
        'qty_step': 50,
        'allow_amount_purchase': true,
      });

      expect(parsed.isMeasured, isTrue);
      expect(parsed.displayStock, 12.5);
      expect(parsed.formatQuantity(250), '250 غ');
      expect(parsed.formatQuantity(1500), '1.5 كغ');
      expect(parsed.pricePerUnit, 1.75);
      expect(parsed.allowAmountPurchase, isTrue);
    });
  });
}
