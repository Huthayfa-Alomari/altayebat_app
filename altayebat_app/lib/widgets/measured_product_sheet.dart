import 'package:flutter/material.dart';

import '../models/product.dart';

class ProductSelection {
  final int quantity;
  final double? requestedAmount;

  const ProductSelection({required this.quantity, this.requestedAmount});
}

Future<ProductSelection?> showMeasuredProductSheet(
  BuildContext context,
  Product product, {
  int? currentQuantity,
  double? currentRequestedAmount,
}) {
  return showModalBottomSheet<ProductSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MeasuredProductSheet(
      product: product,
      currentQuantity: currentQuantity,
      currentRequestedAmount: currentRequestedAmount,
    ),
  );
}

class _MeasuredProductSheet extends StatefulWidget {
  final Product product;
  final int? currentQuantity;
  final double? currentRequestedAmount;

  const _MeasuredProductSheet({
    required this.product,
    this.currentQuantity,
    this.currentRequestedAmount,
  });

  @override
  State<_MeasuredProductSheet> createState() => _MeasuredProductSheetState();
}

class _MeasuredProductSheetState extends State<_MeasuredProductSheet> {
  final _quantityController = TextEditingController();
  final _amountController = TextEditingController();
  String? _error;

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    final current = widget.currentQuantity;
    if (current != null && current > 0) {
      _quantityController.text = (current / product.inventoryScale)
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    final amount = widget.currentRequestedAmount;
    if (amount != null && amount > 0) {
      _amountController.text = amount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<int> get _quickQuantities {
    final base = product.isWeight
        ? <int>[250, 500, 1000, 2000]
        : <int>[250, 500, 1000, 2000];
    return base
        .where((value) => value >= product.minQty && value <= product.stockQty)
        .toSet()
        .toList(growable: false);
  }

  int _nearestValidQuantity(int quantity) {
    final step = product.qtyStep > 0 ? product.qtyStep : 1;
    var normalized = quantity;

    if (step > 1) {
      normalized = ((normalized / step).round() * step);
    }

    if (normalized < product.minQty) {
      normalized = ((product.minQty + step - 1) ~/ step) * step;
    }

    if (normalized > product.stockQty && step > 1) {
      normalized = (product.stockQty ~/ step) * step;
    }

    return normalized;
  }

  ProductSelection? _quantitySelection(int quantity) {
    final normalized = _nearestValidQuantity(quantity);

    if (normalized <= 0 ||
        normalized < product.minQty ||
        normalized > product.stockQty) {
      setState(() => _error = 'الكمية المطلوبة أكبر من المتوفر حاليًا.');
      return null;
    }
    return ProductSelection(quantity: normalized);
  }

  ProductSelection? _amountSelection(double amount) {
    if (!product.allowAmountPurchase || amount <= 0 || product.price <= 0) {
      setState(() => _error = 'المبلغ غير صالح.');
      return null;
    }

    // The checkout contract validates the product quantity step. Convert the
    // requested JOD amount to grams/ml, then snap to the nearest valid step so
    // values such as 571 g do not reach the server as INVALID_ITEM.
    final rawQuantity = (amount / product.price).round();
    final quantity = _nearestValidQuantity(rawQuantity);

    if (quantity <= 0 ||
        quantity < product.minQty ||
        quantity > product.stockQty) {
      setState(() => _error = 'المبلغ المطلوب يحتاج كمية أكبر من المتوفر.');
      return null;
    }

    return ProductSelection(quantity: quantity, requestedAmount: amount);
  }

  void _pickQuantity(int quantity) {
    final selection = _quantitySelection(quantity);
    if (selection != null) Navigator.of(context).pop(selection);
  }

  void _pickAmount(double amount) {
    final selection = _amountSelection(amount);
    if (selection != null) Navigator.of(context).pop(selection);
  }

  void _submitCustomQuantity() {
    final units = double.tryParse(_quantityController.text.trim());
    if (units == null || units <= 0) {
      setState(() => _error = 'اكتب كمية صحيحة.');
      return;
    }
    _pickQuantity((units * product.inventoryScale).round());
  }

  void _submitCustomAmount() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'اكتب مبلغًا صحيحًا.');
      return;
    }
    _pickAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quickQuantities = _quickQuantities;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              product.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${product.pricePerUnit.toStringAsFixed(2)} د.أ لكل ${product.unitLabel} • المتوفر ${product.stockLabel}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'اختر الكمية',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (quickQuantities.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quickQuantities
                    .map(
                      (quantity) => ActionChip(
                        label: Text(product.formatQuantity(quantity)),
                        onPressed: () => _pickQuantity(quantity),
                      ),
                    )
                    .toList(growable: false),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'كمية أخرى بالـ${product.unitLabel}',
                      hintText: product.isWeight ? 'مثال: 0.75' : 'مثال: 1.5',
                    ),
                    onSubmitted: (_) => _submitCustomQuantity(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submitCustomQuantity,
                  child: const Text('اختيار'),
                ),
              ],
            ),
            if (product.allowAmountPurchase) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Divider(),
              ),
              const Text(
                'أو اطلب حسب المبلغ',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'مثلاً: عدس بنصف دينار أو بدينار. سنحسب الوزن التقريبي تلقائيًا.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [0.5, 1.0, 2.0, 5.0]
                    .map(
                      (amount) => ActionChip(
                        label: Text(
                          '${amount.toStringAsFixed(amount < 1 ? 2 : 0)} د.أ',
                        ),
                        onPressed: () => _pickAmount(amount),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'مبلغ آخر (د.أ)',
                        hintText: 'مثال: 1.50',
                      ),
                      onSubmitted: (_) => _submitCustomAmount(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submitCustomAmount,
                    child: const Text('اختيار'),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
