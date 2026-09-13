import 'product.dart';

class CartItem {
  final Product product;
  int quantity;

  /// When the customer chose "buy by value", keep the requested value only as
  /// a UX hint. Checkout still receives the server-verifiable atomic quantity.
  double? requestedAmount;

  CartItem({required this.product, this.quantity = 1, this.requestedAmount});

  double get subtotal => product.price * quantity;

  bool get isMeasured => product.isMeasured;

  String get quantityLabel => product.formatQuantity(quantity);
}
