import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../models/cart_item.dart';

class CartProvider extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => UnmodifiableListView(_items.values);

  /// Badge count: pieces keep their natural count; a measured product counts as
  /// one cart line so 500 grams never appears as "500 items".
  int get itemCount => _items.values.fold(
    0,
    (sum, item) => sum + (item.product.isMeasured ? 1 : item.quantity),
  );

  int get lineCount => _items.length;

  double get total =>
      _items.values.fold(0.0, (sum, item) => sum + item.subtotal);

  bool get isEmpty => _items.isEmpty;

  /// Piece-product convenience used by the normal + button.
  bool add(Product product) {
    if (product.isMeasured) return false;
    if (!product.isAvailable || product.stockQty <= 0) return false;

    final current = _items[product.id];
    if (current != null) {
      if (current.quantity >= product.stockQty) return false;
      current.quantity++;
      current.requestedAmount = null;
    } else {
      _items[product.id] = CartItem(product: product);
    }

    notifyListeners();
    return true;
  }

  /// Sets an exact atomic quantity. For measured products the quantity is grams
  /// or millilitres; for pieces it is a piece count.
  bool setQuantity(Product product, int quantity, {double? requestedAmount}) {
    if (!product.isAvailable || product.stockQty <= 0) return false;
    if (quantity <= 0 || quantity > product.stockQty) return false;
    if (quantity < product.minQty) return false;

    if (!product.isMeasured && quantity % product.qtyStep != 0) return false;

    _items[product.id] = CartItem(
      product: product,
      quantity: quantity,
      requestedAmount: requestedAmount,
    );
    notifyListeners();
    return true;
  }

  void decrement(Product product) {
    final current = _items[product.id];
    if (current == null) return;

    if (product.isMeasured) {
      remove(product.id);
      return;
    }

    if (current.quantity > 1) {
      current.quantity--;
      current.requestedAmount = null;
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

  CartItem? itemFor(String productId) => _items[productId];

  bool canAdd(Product product) {
    if (product.isMeasured) return false;
    if (!product.isAvailable || product.stockQty <= 0) return false;
    return quantityOf(product.id) < product.stockQty;
  }
}
