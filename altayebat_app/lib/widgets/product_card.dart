import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../theme/app_theme.dart';

class ProductCard extends StatelessWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final qty = cart.quantityOf(product.id);
    final canAdd = cart.canAdd(product);
    final outOfStock = !product.isAvailable || product.stockQty <= 0;

    return Semantics(
      container: true,
      label: '${product.name}، ${product.price.toStringAsFixed(2)} دينار',
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: outOfStock ? 0.45 : 1,
              child: Container(
                height: 104,
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network(
                          product.imageUrl!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.textSecondary,
                              size: 32,
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.shopping_basket_outlined,
                          color: AppColors.primary,
                          size: 32,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${product.price.toStringAsFixed(2)} د.أ',
              style: const TextStyle(
                fontSize: 16,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 18,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _stockLabel(outOfStock),
              ),
            ),
            const Spacer(),
            if (qty == 0)
              _addButton(context, enabled: canAdd, outOfStock: outOfStock)
            else
              _stepper(context, qty, canAdd: canAdd),
          ],
        ),
      ),
    );
  }

  Widget _stockLabel(bool outOfStock) {
    if (outOfStock) {
      return const Text(
        'غير متوفر حاليًا',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.redAccent,
        ),
      );
    }

    if (product.stockQty <= 3) {
      return Text(
        'متبقي ${product.stockQty} فقط',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _addButton(
    BuildContext context, {
    required bool enabled,
    required bool outOfStock,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled
          ? 'أضف ${product.name} للسلة'
          : '${product.name} غير متوفر',
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: FilledButton.icon(
          onPressed: enabled
              ? () {
                  final added = context.read<CartProvider>().add(product);
                  if (!added) _showStockMessage(context);
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.border,
            disabledForegroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(
            outOfStock ? Icons.block_outlined : Icons.add_shopping_cart_rounded,
            size: 19,
          ),
          label: Text(
            outOfStock ? 'غير متوفر' : 'أضف',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Widget _stepper(BuildContext context, int qty, {required bool canAdd}) {
    return Semantics(
      container: true,
      label: 'الكمية في السلة $qty',
      child: Container(
        width: double.infinity,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: IconButton(
                tooltip: qty == 1 ? 'إزالة من السلة' : 'تقليل الكمية',
                padding: EdgeInsets.zero,
                icon: Icon(
                  qty == 1
                      ? Icons.delete_outline_rounded
                      : Icons.remove_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () =>
                    context.read<CartProvider>().decrement(product),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 36),
              alignment: Alignment.center,
              child: Text(
                '$qty',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: IconButton(
                tooltip: canAdd ? 'زيادة الكمية' : 'وصلت للكمية المتوفرة',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.add_rounded,
                  color: canAdd ? Colors.white : Colors.white54,
                  size: 21,
                ),
                onPressed: canAdd
                    ? () {
                        final added = context.read<CartProvider>().add(product);
                        if (!added) _showStockMessage(context);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStockMessage(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('وصلت للكمية المتوفرة من المنتج'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
