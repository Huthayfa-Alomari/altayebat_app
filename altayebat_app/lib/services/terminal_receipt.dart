class TerminalReceipt {
  TerminalReceipt._();

  static String quantityLabel(Map<String, dynamic> item) {
    final saleType = item['sale_type_snapshot']?.toString() ?? 'piece';
    final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
    if (saleType == 'piece') return '$quantity';

    final scale = (item['inventory_scale_snapshot'] as num?)?.toInt() ?? 1000;
    if (quantity < scale) {
      return '$quantity ${saleType == 'weight' ? 'غ' : 'مل'}';
    }

    final units = quantity / scale;
    final text = units == units.roundToDouble()
        ? units.toStringAsFixed(0)
        : units.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$text ${saleType == 'weight' ? 'كغ' : 'لتر'}';
  }

  static String unitPriceLabel(Map<String, dynamic> item) {
    final saleType = item['sale_type_snapshot']?.toString() ?? 'piece';
    final displayPrice = (item['display_unit_price_snapshot'] as num?)?.toDouble() ??
        (item['unit_price'] as num?)?.toDouble() ??
        0;
    final unit = saleType == 'weight'
        ? 'كغ'
        : saleType == 'volume'
            ? 'لتر'
            : 'قطعة';
    return '${displayPrice.toStringAsFixed(3)} د.أ/$unit';
  }

  static String build(Map<String, dynamic> order) {
    final id = order['id']?.toString() ?? '';
    final shortId = id.length >= 8 ? id.substring(0, 8).toUpperCase() : id;
    final customerRaw = order['customers'];
    final customer = customerRaw is Map
        ? Map<String, dynamic>.from(customerRaw)
        : <String, dynamic>{};
    final itemsRaw = order['items'];
    final items = itemsRaw is List
        ? itemsRaw.map((row) => Map<String, dynamic>.from(row as Map)).toList()
        : <Map<String, dynamic>>[];

    final buffer = StringBuffer()
      ..writeln('أسواق الطيبات')
      ..writeln('طلب #$shortId')
      ..writeln('------------------------------');

    final customerName = customer['name']?.toString().trim();
    final customerPhone = customer['phone']?.toString().trim();
    if (customerName != null && customerName.isNotEmpty) {
      buffer.writeln('الزبون: $customerName');
    }
    if (customerPhone != null && customerPhone.isNotEmpty) {
      buffer.writeln('الهاتف: $customerPhone');
    }
    buffer.writeln('------------------------------');

    for (final item in items) {
      final productRaw = item['products'];
      final product = productRaw is Map
          ? Map<String, dynamic>.from(productRaw)
          : <String, dynamic>{};
      final name = product['name']?.toString() ?? 'منتج';
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
      final atomicPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
      final lineTotal = atomicPrice * quantity;

      buffer
        ..writeln(name)
        ..writeln('${quantityLabel(item)} • ${unitPriceLabel(item)}')
        ..writeln('${lineTotal.toStringAsFixed(2)} د.أ');
    }

    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final paymentMethod = switch (order['payment_method']?.toString()) {
      'cash' => 'كاش',
      'cliq' => 'CliQ',
      'card' => 'بطاقة',
      final value => value ?? '—',
    };

    buffer
      ..writeln('------------------------------')
      ..writeln('المجموع: ${total.toStringAsFixed(2)} د.أ')
      ..writeln('الدفع: $paymentMethod')
      ..writeln('------------------------------')
      ..writeln('شكرًا لتسوقكم من أسواق الطيبات');

    return buffer.toString();
  }
}
