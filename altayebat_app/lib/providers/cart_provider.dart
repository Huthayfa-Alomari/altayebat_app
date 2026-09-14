import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => UnmodifiableListView(_items.values);

  int get lineCount => _items.length;

  int get itemCount => _items.values.fold(
    0,
    (sum, item) => sum + (item.product.isMeasured ? 1 : item.quantity),
  );

  double get total =>
      _items.values.fold(0.0, (sum, item) => sum + item.subtotal);

  bool get isEmpty => _items.isEmpty;

  bool add(Product product) {
    if (!product.isAvailable || product.stockQty <= 0) return false;

    final current = _items[product.id];
    if (current != null) {
      final nextQuantity = current.quantity + product.cartStep;
      if (nextQuantity > product.stockQty) return false;
      current.quantity = nextQuantity;
    } else {
      final initialQuantity = product.initialCartQuantity;
      if (initialQuantity > product.stockQty) return false;
      _items[product.id] = CartItem(
        product: product,
        quantity: initialQuantity,
      );
    }

    notifyListeners();
    return true;
  }

  void decrement(Product product) {
    final current = _items[product.id];
    if (current == null) return;

    if (current.quantity <= product.initialCartQuantity) {
      _items.remove(product.id);
    } else {
      final nextQuantity = current.quantity - product.cartStep;
      current.quantity = nextQuantity < product.initialCartQuantity
          ? product.initialCartQuantity
          : nextQuantity;
    }
    notifyListeners();
  }

  void remove(String productId) {
    if (_items.remove(productId) != null) {
      notifyListeners();
    }
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  int quantityOf(String productId) => _items[productId]?.quantity ?? 0;

  bool canAdd(Product product) {
    if (!product.isAvailable || product.stockQty <= 0) return false;

    final currentQuantity = quantityOf(product.id);
    if (currentQuantity == 0) {
      return product.initialCartQuantity <= product.stockQty;
    }

    return currentQuantity + product.cartStep <= product.stockQty;
  }
}
