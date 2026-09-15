import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/measured_product_sheet.dart';
import 'cart_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Product product;

  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  List<Product> _related = const [];
  final Set<String> _selectedRelated = <String>{};
  bool _loadingRelated = true;

  @override
  void initState() {
    super.initState();
    _loadRelated();
  }

  Future<void> _loadRelated() async {
    try {
      final items = await CatalogService.fetchRelatedProducts(
        product: widget.product,
        limit: 4,
      );
      if (!mounted) return;
      setState(() {
        _related = items;
        _selectedRelated
          ..clear()
          ..addAll(
            items
                .where((product) => !product.isMeasured)
                .take(2)
                .map((product) => product.id),
          );
        _loadingRelated = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRelated = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final product = widget.product;
    final qty = cart.quantityOf(product.id);
    final outOfStock = !product.isAvailable || product.stockQty <= 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('تفاصيل المنتج'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Badge.count(
              count: cart.itemCount,
              isLabelVisible: cart.itemCount > 0,
              child: IconButton(
                tooltip: 'السلة',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  );
                },
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 128),
        children: [
          _ProductHero(product: product, outOfStock: outOfStock),
          const SizedBox(height: 18),
          Text(
            product.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  product.priceLabel,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _AvailabilityPill(product: product),
            ],
          ),
          if (product.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 18),
            const Text(
              'عن المنتج',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              product.description!.trim(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _relatedSection(cart),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          elevation: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _primaryAction(cart, qty, outOfStock: outOfStock),
          ),
        ),
      ),
    );
  }

  Widget _primaryAction(
    CartProvider cart,
    int qty, {
    required bool outOfStock,
  }) {
    final product = widget.product;

    if (outOfStock) {
      return SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.block_outlined),
          label: const Text('غير متوفر حاليًا'),
        ),
      );
    }

    if (product.isMeasured) {
      return SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: _chooseMeasured,
          icon: const Icon(Icons.scale_outlined),
          label: Text(
            qty > 0
                ? 'تعديل الكمية • ${product.formatQuantity(qty)}'
                : 'اختر الكمية',
          ),
        ),
      );
    }

    if (qty == 0) {
      return SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: cart.canAdd(product)
              ? () => _addCurrentProduct(cart)
              : null,
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('أضف للسلة'),
        ),
      );
    }

    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: IconButton(
              tooltip: qty == 1 ? 'إزالة من السلة' : 'تقليل الكمية',
              onPressed: () => cart.decrement(product),
              icon: Icon(
                qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'في السلة',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$qty',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 58,
            child: IconButton(
              tooltip: cart.canAdd(product)
                  ? 'زيادة الكمية'
                  : 'وصلت للكمية المتوفرة',
              onPressed: cart.canAdd(product)
                  ? () => _addCurrentProduct(cart)
                  : null,
              icon: Icon(
                Icons.add_rounded,
                color: cart.canAdd(product) ? Colors.white : Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedSection(CartProvider cart) {
    if (_loadingRelated) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_related.isEmpty) return const SizedBox.shrink();

    final selectedProducts = _related
        .where((product) => _selectedRelated.contains(product.id))
        .toList(growable: false);
    final selectedTotal = selectedProducts.fold<double>(
      0,
      (sum, product) => sum + product.pricePerUnit,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'عادةً يُشترى معه',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'اختيارات تكمل المنتج وتوفّر عليك البحث',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        ..._related.map(
          (product) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RelatedProductTile(
              product: product,
              selected: _selectedRelated.contains(product.id),
              onSelected: product.isMeasured
                  ? null
                  : (value) {
                      setState(() {
                        if (value) {
                          _selectedRelated.add(product.id);
                        } else {
                          _selectedRelated.remove(product.id);
                        }
                      });
                    },
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailsScreen(product: product),
                  ),
                );
              },
            ),
          ),
        ),
        if (selectedProducts.isNotEmpty)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _addSelectedRelated(cart, selectedProducts),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: Text(
                'أضف المحدد للسلة • ${selectedTotal.toStringAsFixed(2)} د.أ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  void _addCurrentProduct(CartProvider cart) {
    final added = cart.add(widget.product);
    if (!added) _showMessage('وصلت للكمية المتوفرة من المنتج');
  }

  Future<void> _chooseMeasured() async {
    final cart = context.read<CartProvider>();
    final current = cart.itemFor(widget.product.id);
    final selection = await showMeasuredProductSheet(
      context,
      widget.product,
      currentQuantity: current?.quantity,
      currentRequestedAmount: current?.requestedAmount,
    );
    if (selection == null || !mounted) return;

    final updated = cart.setQuantity(
      widget.product,
      selection.quantity,
      requestedAmount: selection.requestedAmount,
    );
    if (!updated) _showMessage('الكمية المطلوبة غير متوفرة حاليًا');
  }

  void _addSelectedRelated(CartProvider cart, List<Product> products) {
    var addedCount = 0;
    for (final product in products) {
      if (product.isMeasured) continue;
      if (cart.add(product)) addedCount++;
    }

    if (addedCount == 0) {
      _showMessage('المنتجات المحددة موجودة في السلة أو وصلت للكمية المتوفرة');
      return;
    }
    _showMessage('تمت إضافة $addedCount من المنتجات المقترحة للسلة');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _ProductHero extends StatelessWidget {
  final Product product;
  final bool outOfStock;

  const _ProductHero({required this.product, required this.outOfStock});

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imageUrl?.trim().isNotEmpty == true;

    return Opacity(
      opacity: outOfStock ? 0.55 : 1,
      child: Container(
        height: 290,
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: hasImage
            ? Image.network(
                product.imageUrl!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.textSecondary,
                  size: 52,
                ),
              )
            : const Icon(
                Icons.shopping_basket_outlined,
                color: AppColors.primary,
                size: 64,
              ),
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  final Product product;

  const _AvailabilityPill({required this.product});

  @override
  Widget build(BuildContext context) {
    final available = product.isAvailable && product.stockQty > 0;
    final text = available
        ? product.isMeasured
              ? 'متوفر ${product.stockLabel}'
              : product.stockQty <= 3
              ? 'متبقي ${product.stockQty}'
              : 'متوفر'
        : 'غير متوفر';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: available
            ? AppColors.skySoft
            : Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: available ? AppColors.skyBlueDark : Colors.redAccent,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RelatedProductTile extends StatelessWidget {
  final Product product;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback onOpen;

  const _RelatedProductTile({
    required this.product,
    required this.selected,
    required this.onSelected,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = product.imageUrl?.trim().isNotEmpty == true;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  value: selected,
                  onChanged: onSelected == null
                      ? null
                      : (value) => onSelected!(value ?? false),
                ),
              ),
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.softSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: hasImage
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.shopping_basket_outlined,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : const Icon(
                        Icons.shopping_basket_outlined,
                        color: AppColors.primary,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.priceLabel,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (product.isMeasured)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'افتح المنتج لاختيار الكمية',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
