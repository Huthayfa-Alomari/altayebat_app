import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => UnmodifiableListView(_items.values);

  int get itemCount => _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get total =>
      _items.values.fold(0.0, (sum, item) => sum + item.subtotal);

  bool get isEmpty => _items.isEmpty;

  bool add(Product product) {
    if (!product.isAvailable || product.stockQty <= 0) return false;

    final current = _items[product.id];
    if (current != null) {
      if (current.quantity >= product.stockQty) return false;
      current.quantity++;
    } else {
      _items[product.id] = CartItem(product: product);
    }

    notifyListeners();
    return true;
  }

  void decrement(Product product) {
    final current = _items[product.id];
    if (current == null) return;

    if (current.quantity > 1) {
      current.quantity--;
    } else {
      _items.remove(product.id);
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
    return quantityOf(product.id) < product.stockQty;
  }
}
