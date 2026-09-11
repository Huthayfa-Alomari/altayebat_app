import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cart_provider.dart';
import '../services/cart_bridge.dart';
import '../services/supabase_service.dart';
import '../widgets/store_open_banner.dart';
import 'barcode_scanner_screen.dart';
import 'delivery_checkout_screen.dart';
import 'customer_auth_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final CartProvider typedCart = context.watch<CartProvider>();
    final dynamic cart = typedCart;
    final lines = CartBridge.snapshot(cart);
    final totalItems = CartBridge.totalItems(cart);
    final subtotal = CartBridge.subtotal(cart);

    return Scaffold(
      appBar: AppBar(
        title: const Text('السلة'),
      ),
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
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      return _CartLineCard(
                        line: line,
                        onIncrement: () =>
                            _changeQuantity(context, cart, line, true),
                        onDecrement: () =>
                            _changeQuantity(context, cart, line, false),
                        onRemove: () => _remove(context, cart, line),
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
                color: theme.colorScheme.surface,
                elevation: 14,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                                Text(
                                  'الإجمالي',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$totalItems ${totalItems == 1 ? 'قطعة' : 'قطع'}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${subtotal.toStringAsFixed(2)} د.أ',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'رسوم التوصيل والسعر النهائي تُحسب حسب موقعك قبل تأكيد الطلب.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _checkout(context, cart),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 17,
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
    );
  }

  Future<bool> _hasCompleteCustomerProfile() async {
    if (!SupabaseService.isSignedIn) return false;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

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

  Future<void> _checkout(BuildContext context, dynamic cart) async {
    final hasProfile = await _hasCompleteCustomerProfile();
    if (!context.mounted) return;

    if (!hasProfile) {
      final authenticated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const CustomerAuthScreen(returnAfterSuccess: true),
        ),
      );

      if (authenticated != true || !context.mounted) return;

      final profileNowComplete = await _hasCompleteCustomerProfile();
      if (!context.mounted) return;
      if (!profileNowComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('احفظ اسمك ورقم الموبايل قبل إتمام الطلب.'),
          ),
        );
        return;
      }
    }

    try {
      final items = CartBridge.toRpcItems(cart);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DeliveryCheckoutScreen(
            items: items,
            onOrderCreated: () => CartBridge.clear(cart),
          ),
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

  void _changeQuantity(
    BuildContext context,
    dynamic cart,
    CartBridgeLine line,
    bool increase,
  ) {
    final changed = increase
        ? CartBridge.increment(cart, line)
        : CartBridge.decrement(cart, line);

    if (!changed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر تعديل الكمية')));
    }
  }

  void _remove(BuildContext context, dynamic cart, CartBridgeLine line) {
    final removed = CartBridge.remove(cart, line);
    if (!removed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر حذف المنتج من السلة')));
    }
  }
}

class _CartLineCard extends StatelessWidget {
  final CartBridgeLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartLineCard({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockQty = line.stockQty;
    final outOfStock = stockQty != null && stockQty <= 0;
    final canIncrement =
        !outOfStock && (stockQty == null || line.quantity < stockQty);
    final lineTotal = line.subtotal;

    return Semantics(
      container: true,
      label:
          '${line.name}، الكمية ${line.quantity}، المجموع ${lineTotal.toStringAsFixed(2)} دينار',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CartProductImage(imageUrl: line.imageUrl),
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
                          line.name,
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
                    '${line.price.toStringAsFixed(2)} د.أ للقطعة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (outOfStock) ...[
                    const SizedBox(height: 4),
                    Text(
                      'المنتج غير متوفر حاليًا',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else if (stockQty != null &&
                      stockQty > 0 &&
                      stockQty <= 3) ...[
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
                      _QuantityControl(
                        quantity: line.quantity,
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
    final theme = Theme.of(context);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
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
            height: 48,
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
            const Icon(
              Icons.shopping_cart_outlined,
              size: 62,
              color: Color(0xFF9CA3AF),
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
