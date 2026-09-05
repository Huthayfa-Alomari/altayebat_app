import '../models/product.dart';

class CartBridgeLine {
  final dynamic source;
  final dynamic product;
  final String productId;
  final String name;
  final double price;
  final int quantity;
  final String? imageUrl;
  final int? stockQty;

  const CartBridgeLine({
    required this.source,
    required this.product,
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    this.imageUrl,
    this.stockQty,
  });

  double get subtotal => price * quantity;
}

class CartBridge {
  const CartBridge._();

  static List<CartBridgeLine> snapshot(dynamic cart) {
    dynamic raw = _missing;

    try {
      raw = cart.lines;
    } catch (_) {}

    if (identical(raw, _missing)) {
      try {
        raw = cart.items;
      } catch (_) {}
    }

    if (identical(raw, _missing)) {
      try {
        raw = cart.cartItems;
      } catch (_) {}
    }

    if (identical(raw, _missing)) {
      try {
        raw = cart.products;
      } catch (_) {}
    }

    if (identical(raw, _missing)) {
      try {
        raw = cart.cart;
      } catch (_) {}
    }

    if (identical(raw, _missing) || raw == null) {
      return const [];
    }

    final parsed = <CartBridgeLine>[];

    if (raw is Map) {
      for (final entry in raw.entries) {
        final line = _parseLine(cart: cart, key: entry.key, value: entry.value);
        if (line != null) parsed.add(line);
      }
    } else if (raw is Iterable) {
      for (final value in raw) {
        final line = _parseLine(cart: cart, key: null, value: value);
        if (line != null) parsed.add(line);
      }
    }

    return _merge(parsed);
  }

  static int totalItems(dynamic cart) {
    try {
      final value = cart.totalItems;
      if (value is num) return value.toInt();
    } catch (_) {}

    try {
      final value = cart.totalQuantity;
      if (value is num) return value.toInt();
    } catch (_) {}

    try {
      final value = cart.totalItemQuantity;
      if (value is num) return value.toInt();
    } catch (_) {}

    return snapshot(cart).fold<int>(0, (sum, line) => sum + line.quantity);
  }

  static double subtotal(dynamic cart) {
    try {
      final value = cart.estimatedSubtotal;
      if (value is num) return value.toDouble();
    } catch (_) {}

    try {
      final value = cart.totalAmount;
      if (value is num) return value.toDouble();
    } catch (_) {}

    try {
      final value = cart.total;
      if (value is num) return value.toDouble();
    } catch (_) {}

    try {
      final value = cart.subtotal;
      if (value is num) return value.toDouble();
    } catch (_) {}

    return snapshot(cart).fold<double>(0, (sum, line) => sum + line.subtotal);
  }

  static bool isEmpty(dynamic cart) => snapshot(cart).isEmpty;

  static List<Map<String, dynamic>> toRpcItems(dynamic cart) {
    final items = snapshot(cart)
        .where((line) => line.productId.isNotEmpty && line.quantity > 0)
        .map(
          (line) => <String, dynamic>{
            'product_id': line.productId,
            'quantity': line.quantity,
          },
        )
        .toList(growable: false);

    if (items.isEmpty) {
      throw StateError(
        'تعذر قراءة منتجات السلة. أعد إضافة المنتجات وحاول مرة ثانية.',
      );
    }

    return items;
  }

  static bool increment(dynamic cart, CartBridgeLine line) {
    if (line.product != null) {
      if (_attempt(() => cart.increment(line.product))) return true;
      if (_attempt(() => cart.add(line.product))) return true;
      if (_attempt(() => cart.addItem(line.product))) return true;
      if (_attempt(() => cart.addToCart(line.product))) return true;
      if (_attempt(() => cart.addProduct(line.product))) return true;
    }

    if (_attempt(() => cart.increment(line.productId))) return true;
    if (_attempt(() => cart.increaseQuantity(line.productId))) return true;
    if (_attempt(() => cart.addItem(line.productId, line.name, line.price))) {
      return true;
    }

    return false;
  }

  static bool decrement(dynamic cart, CartBridgeLine line) {
    if (_attempt(() => cart.decrement(line.productId))) return true;
    if (line.product != null && _attempt(() => cart.decrement(line.product))) {
      return true;
    }
    if (_attempt(() => cart.decreaseQuantity(line.productId))) return true;
    if (_attempt(() => cart.removeSingle(line.productId))) return true;
    if (_attempt(
      () =>
          cart.reduceItem(line.productId, line.name, line.quantity, line.price),
    )) {
      return true;
    }

    return false;
  }

  static bool remove(dynamic cart, CartBridgeLine line) {
    if (_attempt(() => cart.remove(line.productId))) return true;
    if (_attempt(() => cart.removeItem(line.productId))) return true;
    if (_attempt(() => cart.deleteItem(line.productId))) return true;
    if (line.product != null && _attempt(() => cart.remove(line.product))) {
      return true;
    }
    return false;
  }

  static bool clear(dynamic cart) {
    if (_attempt(() => cart.clear())) return true;
    if (_attempt(() => cart.clearCart())) return true;
    if (_attempt(() => cart.removeAll())) return true;
    return false;
  }

  static bool addProduct(dynamic cart, Product product) {
    if (_attempt(() => cart.add(product))) return true;
    if (_attempt(() => cart.addItem(product))) return true;
    if (_attempt(() => cart.addToCart(product))) return true;
    if (_attempt(() => cart.addProduct(product))) return true;
    if (_attempt(() => cart.increment(product))) return true;
    if (_attempt(() => cart.addItem(product.id, product.name, product.price))) {
      return true;
    }
    return false;
  }

  static CartBridgeLine? _parseLine({
    required dynamic cart,
    required dynamic key,
    required dynamic value,
  }) {
    dynamic product;

    if (key is Product) {
      product = key;
    }

    if (product == null && value is Product) {
      product = value;
    }

    if (product == null) {
      try {
        product = value.product;
      } catch (_) {}
    }

    if (product == null) {
      try {
        product = value.item;
      } catch (_) {}
    }

    if (product == null) {
      try {
        product = value.foodItem;
      } catch (_) {}
    }

    if (product == null && key != null && key is! String && key is! num) {
      product = key;
    }

    var productId = _readId(product);
    if (productId.isEmpty) productId = _readId(value);
    if (productId.isEmpty && key is String) productId = key;

    var quantity = _readQuantity(value);
    if (quantity <= 0 && product != null) {
      quantity = _quantityFromCart(cart, productId, product);
    }
    if (quantity <= 0 && value is num) quantity = value.toInt();
    if (quantity <= 0) quantity = 1;

    final name = _readName(product).isNotEmpty
        ? _readName(product)
        : _readName(value);
    final price = _readPrice(product) > 0
        ? _readPrice(product)
        : _readPrice(value);
    final imageUrl = _readImageUrl(product) ?? _readImageUrl(value);
    final stockQty = _readStockQty(product) ?? _readStockQty(value);

    if (productId.isEmpty && name.isEmpty) return null;

    return CartBridgeLine(
      source: value,
      product: product,
      productId: productId,
      name: name.isEmpty ? productId : name,
      price: price,
      quantity: quantity,
      imageUrl: imageUrl,
      stockQty: stockQty,
    );
  }

  static int _quantityFromCart(
    dynamic cart,
    String productId,
    dynamic product,
  ) {
    if (productId.isNotEmpty) {
      try {
        final value = cart.quantityFor(productId);
        if (value is num) return value.toInt();
      } catch (_) {}

      try {
        final value = cart.getQuantity(productId);
        if (value is num) return value.toInt();
      } catch (_) {}
    }

    try {
      final value = cart.quantityFor(product);
      if (value is num) return value.toInt();
    } catch (_) {}

    return 0;
  }

  static List<CartBridgeLine> _merge(List<CartBridgeLine> lines) {
    final byId = <String, CartBridgeLine>{};

    for (final line in lines) {
      final key = line.productId.isEmpty
          ? '${line.name}|${line.price}'
          : line.productId;
      final existing = byId[key];

      if (existing == null) {
        byId[key] = line;
      } else {
        byId[key] = CartBridgeLine(
          source: existing.source,
          product: existing.product ?? line.product,
          productId: existing.productId.isNotEmpty
              ? existing.productId
              : line.productId,
          name: existing.name.isNotEmpty ? existing.name : line.name,
          price: existing.price > 0 ? existing.price : line.price,
          quantity: existing.quantity + line.quantity,
          imageUrl: existing.imageUrl ?? line.imageUrl,
          stockQty: existing.stockQty ?? line.stockQty,
        );
      }
    }

    return byId.values.toList(growable: false);
  }

  static String _readId(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return (value['id'] ?? value['product_id'] ?? value['productId'])
              ?.toString() ??
          '';
    }

    try {
      return value.id?.toString() ?? '';
    } catch (_) {}

    try {
      return value.productId?.toString() ?? '';
    } catch (_) {}

    return '';
  }

  static String _readName(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return (value['name'] ??
                  value['product_name'] ??
                  value['title'] ??
                  value['productName'])
              ?.toString() ??
          '';
    }

    try {
      return value.name?.toString() ?? '';
    } catch (_) {}

    try {
      return value.title?.toString() ?? '';
    } catch (_) {}

    try {
      return value.productName?.toString() ?? '';
    } catch (_) {}

    return '';
  }

  static double _readPrice(dynamic value) {
    if (value == null) return 0;
    if (value is Map) {
      return _asDouble(
        value['price'] ?? value['unit_price'] ?? value['unitPrice'],
      );
    }

    try {
      return _asDouble(value.price);
    } catch (_) {}

    try {
      return _asDouble(value.unitPrice);
    } catch (_) {}

    return 0;
  }

  static int _readQuantity(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();

    if (value is Map) {
      return _asInt(value['quantity'] ?? value['qty'] ?? value['count']);
    }

    try {
      return _asInt(value.quantity);
    } catch (_) {}

    try {
      return _asInt(value.qty);
    } catch (_) {}

    try {
      return _asInt(value.count);
    } catch (_) {}

    return 0;
  }

  static String? _readImageUrl(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final raw = value['image_url'] ?? value['imageUrl'] ?? value['image'];
      final text = raw?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    try {
      final text = value.imageUrl?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    } catch (_) {}

    try {
      final text = value.image?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    } catch (_) {}

    return null;
  }

  static int? _readStockQty(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final raw = value['stock_qty'] ?? value['stockQty'] ?? value['stock'];
      if (raw == null) return null;
      return _asInt(raw);
    }

    try {
      final raw = value.stockQty;
      if (raw is num) return raw.toInt();
    } catch (_) {}

    try {
      final raw = value.stock;
      if (raw is num) return raw.toInt();
    } catch (_) {}

    return null;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _attempt(void Function() action) {
    try {
      action();
      return true;
    } catch (_) {
      return false;
    }
  }

  static const Object _missing = Object();
}
