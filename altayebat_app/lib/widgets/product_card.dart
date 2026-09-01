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

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 125,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          product.imageUrl!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.textSecondary,
                              size: 34,
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.shopping_basket_outlined,
                          color: AppColors.primary,
                          size: 34,
                        ),
                      ),
              ),
              const SizedBox(height: 9),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${product.price.toStringAsFixed(2)} د.أ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              if (outOfStock)
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Text(
                    'غير متوفر حاليًا',
                    style: TextStyle(fontSize: 10, color: Colors.redAccent),
                  ),
                )
              else if (product.stockQty <= 5)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'متبقي ${product.stockQty}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: qty == 0
                ? _addButton(context, enabled: canAdd)
                : _stepper(context, qty, canAdd: canAdd),
          ),
        ],
      ),
    );
  }

  Widget _addButton(BuildContext context, {required bool enabled}) {
    return Semantics(
      button: true,
      label: 'إضافة ${product.name} للسلة',
      child: InkWell(
        onTap: enabled
            ? () {
                final added = context.read<CartProvider>().add(product);
                if (!added) _showStockMessage(context);
              }
            : null,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: enabled ? AppColors.primary : AppColors.border,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 21),
        ),
      ),
    );
  }

  Widget _stepper(BuildContext context, int qty, {required bool canAdd}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تقليل الكمية',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.remove, color: Colors.white, size: 14),
            onPressed: () => context.read<CartProvider>().decrement(product),
          ),
          Text(
            '$qty',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          IconButton(
            tooltip: canAdd ? 'زيادة الكمية' : 'وصلت للكمية المتوفرة',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              Icons.add,
              color: canAdd ? Colors.white : Colors.white54,
              size: 14,
            ),
            onPressed: canAdd
                ? () {
                    final added = context.read<CartProvider>().add(product);
                    if (!added) _showStockMessage(context);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  void _showStockMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('وصلت للكمية المتوفرة من المنتج')),
    );
  }
}
