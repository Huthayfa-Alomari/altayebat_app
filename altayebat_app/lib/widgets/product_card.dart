import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../screens/product_details_screen.dart';
import '../settings/app_language.dart';
import '../theme/app_theme.dart';
import 'measured_product_sheet.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final bool compact;

  const ProductCard({super.key, required this.product, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cartState = context.select<CartProvider, ({int qty, bool canAdd})>(
      (cart) =>
          (qty: cart.quantityOf(product.id), canAdd: cart.canAdd(product)),
    );
    final qty = cartState.qty;
    final canAdd = cartState.canAdd;
    final outOfStock = !product.isAvailable || product.stockQty <= 0;

    return Semantics(
      container: true,
      button: true,
      label:
          '${product.displayName(AppLanguage.isEnglish(context))}، ${product.priceLabel}، ${AppLanguage.text(context, 'افتح تفاصيل المنتج', 'Open product details')}',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: () => _openDetails(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final imageHeight = (constraints.maxHeight * 0.42).clamp(
                compact ? 96.0 : 108.0,
                compact ? 118.0 : 138.0,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: imageHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 9, 9, 0),
                      child: _imageArea(outOfStock),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 8 : 10,
                        7,
                        compact ? 8 : 10,
                        9,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.displayName(AppLanguage.isEnglish(context)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 12.5,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.isMeasured
                                ? product.unitLabel
                                : _stockText(context, outOfStock),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: outOfStock
                                  ? AppColors.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            product.priceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: compact ? 14.5 : 16.5,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          if (product.isMeasured)
                            _measuredButton(
                              context,
                              qty,
                              outOfStock: outOfStock,
                            )
                          else if (qty == 0)
                            _addButton(
                              context,
                              enabled: canAdd,
                              outOfStock: outOfStock,
                            )
                          else
                            _stepper(context, qty, canAdd: canAdd),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _imageArea(bool outOfStock) {
    return Opacity(
      opacity: outOfStock ? 0.45 : 1,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                  ? Image.network(
                      product.imageUrl!,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      cacheWidth: 480,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFFC3CAD3),
                          size: 38,
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.shopping_basket_outlined,
                        color: AppColors.skyBlue,
                        size: 40,
                      ),
                    ),
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: outOfStock
                    ? AppColors.textSecondary
                    : AppColors.skyBlueDark,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                outOfStock
                    ? 'غير متوفر'
                    : product.isMeasured
                    ? 'بالوزن'
                    : 'متوفر',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stockText(BuildContext context, bool outOfStock) {
    if (outOfStock) {
      return AppLanguage.text(context, 'غير متوفر حاليًا', 'Out of stock');
    }
    if (product.stockQty <= 3) {
      return AppLanguage.isEnglish(context)
          ? 'Only ${product.stockQty} left'
          : 'متبقي ${product.stockQty} فقط';
    }
    return AppLanguage.text(context, 'متوفر الآن', 'In stock');
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product)),
    );
  }

  Widget _measuredButton(
    BuildContext context,
    int qty, {
    required bool outOfStock,
  }) {
    final hasSelection = qty > 0;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: outOfStock ? null : () => _chooseMeasured(context),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(
          outOfStock
              ? Icons.block_outlined
              : hasSelection
              ? Icons.edit_outlined
              : Icons.scale_outlined,
          size: 17,
        ),
        label: Text(
          outOfStock
              ? AppLanguage.text(context, 'غير متوفر', 'Unavailable')
              : hasSelection
              ? product.formatQuantity(qty)
              : AppLanguage.text(context, 'اختر الكمية', 'Choose quantity'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Future<void> _chooseMeasured(BuildContext context) async {
    final cart = context.read<CartProvider>();
    final current = cart.itemFor(product.id);
    final selection = await showMeasuredProductSheet(
      context,
      product,
      currentQuantity: current?.quantity,
      currentRequestedAmount: current?.requestedAmount,
    );
    if (selection == null || !context.mounted) return;

    final added = cart.setQuantity(
      product,
      selection.quantity,
      requestedAmount: selection.requestedAmount,
    );
    if (!added) _showStockMessage(context);
  }

  Widget _addButton(
    BuildContext context, {
    required bool enabled,
    required bool outOfStock,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: enabled
            ? () {
                final added = context.read<CartProvider>().add(product);
                if (!added) _showStockMessage(context);
              }
            : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(
          outOfStock ? Icons.block_outlined : Icons.shopping_cart_outlined,
          size: 17,
        ),
        label: Text(
          outOfStock
              ? AppLanguage.text(context, 'غير متوفر', 'Unavailable')
              : compact
              ? 'أضف'
              : 'أضف للسلة',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _stepper(BuildContext context, int qty, {required bool canAdd}) {
    return Container(
      width: double.infinity,
      height: 48,
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
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                color: Colors.white,
                size: 19,
              ),
              onPressed: () => context.read<CartProvider>().decrement(product),
            ),
          ),
          Text(
            '$qty',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          Expanded(
            child: IconButton(
              tooltip: canAdd ? 'زيادة الكمية' : 'وصلت للكمية المتوفرة',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                Icons.add_rounded,
                color: canAdd ? Colors.white : Colors.white54,
                size: 20,
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
