import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/measured_product_sheet.dart';
import '../widgets/store_open_banner.dart';
import 'barcode_scanner_screen.dart';
import 'customer_auth_screen.dart';
import 'delivery_checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = context.watch<CartProvider>();
    final lines = cart.items;
    final totalLines = cart.lineCount;
    final subtotal = cart.total;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('السلة')),
      body: Column(
        children: [
          const StoreOpenBanner(),
          Expanded(
            child: lines.isEmpty
                ? _EmptyCart(
                    onScan: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BarcodeScannerScreen(),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 176),
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = lines[index];
                      return _CartLineCard(
                        item: item,
                        onIncrement: () => _increment(context, cart, item),
                        onDecrement: () => cart.decrement(item.product),
                        onRemove: () => cart.remove(item.product.id),
                        onEditMeasured: item.product.isMeasured
                            ? () => _editMeasured(context, cart, item)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                elevation: 16,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(0xFFFFF5F6),
                          Colors.white,
                          Color(0xFFF2F8FF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ملخص السلة',
                                    style: TextStyle(
                                      color: AppColors.navy,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$totalLines ${totalLines == 1 ? 'صنف' : 'أصناف'}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${subtotal.toStringAsFixed(2)} د.أ',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'رسوم التوصيل والسعر النهائي تظهر قبل تأكيد الطلب.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _checkout(context, cart),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('متابعة لإتمام الطلب'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Future<bool> _hasVerifiedCustomerProfile() async {
    if (!SupabaseService.isSignedIn) return false;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.isAnonymous) return false;

    try {
      final row = await Supabase.instance.client
          .from('customers')
          .select('name, phone')
          .eq('id', user.id)
          .maybeSingle();

      final name = (row?['name'] as String?)?.trim() ?? '';
      final phone = (row?['phone'] as String?)?.trim() ?? '';
      return name.length >= 2 && RegExp(r'^\+9627\d{8}$').hasMatch(phone);
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkout(BuildContext context, CartProvider cart) async {
    final hasProfile = await _hasVerifiedCustomerProfile();
    if (!context.mounted) return;

    if (!hasProfile) {
      final authenticated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const CustomerAuthScreen(returnAfterSuccess: true),
        ),
      );

      if (authenticated != true || !context.mounted) return;

      final profileNowComplete = await _hasVerifiedCustomerProfile();
      if (!context.mounted) return;
      if (!profileNowComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أكد رقم الموبايل بالـ OTP قبل إتمام الطلب.'),
          ),
        );
        return;
      }
    }

    try {
      final items = cart.items
          .map(
            (item) => <String, dynamic>{
              'product_id': item.product.id,
              // Measured products use atomic integer units (g/ml), so the
              // existing checkout RPC remains authoritative and unchanged.
              'quantity': item.quantity,
            },
          )
          .toList(growable: false);

      if (items.isEmpty) {
        throw StateError('السلة فارغة');
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              DeliveryCheckoutScreen(items: items, onOrderCreated: cart.clear),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _editMeasured(
    BuildContext context,
    CartProvider cart,
    CartItem item,
  ) async {
    final selection = await showMeasuredProductSheet(
      context,
      item.product,
      currentQuantity: item.quantity,
      currentRequestedAmount: item.requestedAmount,
    );
    if (selection == null || !context.mounted) return;

    final updated = cart.setQuantity(
      item.product,
      selection.quantity,
      requestedAmount: selection.requestedAmount,
    );
    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الكمية المطلوبة غير متوفرة حاليًا.')),
      );
    }
  }

  void _increment(BuildContext context, CartProvider cart, CartItem item) {
    final added = cart.add(item.product);
    if (added) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('وصلت للكمية المتوفرة من هذا المنتج')),
    );
  }
}

class _CartLineCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final VoidCallback? onEditMeasured;

  const _CartLineCard({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.onEditMeasured,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = item.product;
    final stockQty = product.stockQty;
    final outOfStock = !product.isAvailable || stockQty <= 0;
    final canIncrement = !outOfStock && item.quantity < stockQty;
    final lineTotal = item.subtotal;

    return Semantics(
      container: true,
      label:
          '${product.name}، الكمية ${item.quantityLabel}، المجموع ${lineTotal.toStringAsFixed(2)} دينار',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CartProductImage(imageUrl: product.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'حذف المنتج من السلة',
                        onPressed: onRemove,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: theme.colorScheme.error,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.priceLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (product.isMeasured) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.requestedAmount != null
                          ? 'طلب بقيمة ${item.requestedAmount!.toStringAsFixed(2)} د.أ • حوالي ${item.quantityLabel}'
                          : 'الكمية: ${item.quantityLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (outOfStock) ...[
                    const SizedBox(height: 4),
                    Text(
                      'المنتج غير متوفر حاليًا',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else if (!product.isMeasured && stockQty <= 3) ...[
                    const SizedBox(height: 4),
                    Text(
                      'متبقي $stockQty فقط',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${lineTotal.toStringAsFixed(2)} د.أ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (product.isMeasured)
                        OutlinedButton.icon(
                          onPressed: onEditMeasured,
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: Text(item.quantityLabel),
                        )
                      else
                        _QuantityControl(
                          quantity: item.quantity,
                          canIncrement: canIncrement,
                          onIncrement: onIncrement,
                          onDecrement: onDecrement,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartProductImage extends StatelessWidget {
  final String? imageUrl;

  const _CartProductImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Container(
      width: 86,
      height: 86,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imageUrl!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => Icon(
                  Icons.image_not_supported_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Icon(
              Icons.shopping_basket_outlined,
              color: theme.colorScheme.primary,
              size: 32,
            ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  final int quantity;
  final bool canIncrement;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _QuantityControl({
    required this.quantity,
    required this.canIncrement,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 44,
            child: IconButton(
              tooltip: quantity <= 1 ? 'إزالة من السلة' : 'تقليل الكمية',
              padding: EdgeInsets.zero,
              onPressed: onDecrement,
              icon: Icon(
                quantity <= 1
                    ? Icons.delete_outline_rounded
                    : Icons.remove_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 44,
            child: IconButton(
              tooltip: canIncrement ? 'زيادة الكمية' : 'وصلت للكمية المتوفرة',
              padding: EdgeInsets.zero,
              onPressed: canIncrement ? onIncrement : null,
              icon: Icon(
                Icons.add_rounded,
                color: canIncrement ? Colors.white : Colors.white54,
                size: 23,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  final VoidCallback onScan;

  const _EmptyCart({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.skySoft,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.skyBlue.withValues(alpha: 0.15),
                ),
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'سلتك فاضية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'أضف المنتجات من المتجر أو امسح باركود المنتج مباشرة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('امسح باركود'),
            ),
          ],
        ),
      ),
    );
  }
}
