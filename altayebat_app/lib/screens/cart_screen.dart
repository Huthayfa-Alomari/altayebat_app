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
    final CartProvider typedCart = context.watch<CartProvider>();
    final dynamic cart = typedCart;
    final lines = CartBridge.snapshot(cart);
    final totalItems = CartBridge.totalItems(cart);
    final subtotal = CartBridge.subtotal(cart);

    return Scaffold(
      appBar: AppBar(
        title: Text('السلة${totalItems > 0 ? ' ($totalItems)' : ''}'),
        actions: [
          IconButton(
            tooltip: 'امسح باركود',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
            ),
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'بيانات الحساب',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthScreen()),
            ),
            icon: const Icon(Icons.person_outline),
          ),
          if (lines.isNotEmpty)
            TextButton(
              onPressed: () => _clearCart(context, cart),
              child: const Text('إفراغ'),
            ),
        ],
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
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
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      color: Color(0x18000000),
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'مجموع المنتجات',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ),
                        Text(
                          '${subtotal.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'رسوم التوصيل والسعر النهائي تُحسب حسب موقعك قبل تأكيد الطلب.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _checkout(context, cart),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('إتمام الطلب'),
                      ),
                    ),
                  ],
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

  void _clearCart(BuildContext context, dynamic cart) {
    final cleared = CartBridge.clear(cart);
    if (!cleared) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر إفراغ السلة')));
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
    super.key,
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
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
                      const SizedBox(width: 6),
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
                  const SizedBox(height: 3),
                  Text(
                    '${line.price.toStringAsFixed(2)} د.أ للقطعة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (outOfStock) ...[
                    const SizedBox(height: 3),
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
                    const SizedBox(height: 3),
                    Text(
                      'متبقي $stockQty فقط',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
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
      width: 82,
      height: 82,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(9),
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
              size: 30,
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
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
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
                size: 20,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            alignment: Alignment.center,
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: canIncrement ? 'زيادة الكمية' : 'وصلت للكمية المتوفرة',
              padding: EdgeInsets.zero,
              onPressed: canIncrement ? onIncrement : null,
              icon: Icon(
                Icons.add_rounded,
                color: canIncrement ? Colors.white : Colors.white54,
                size: 21,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? const Color(0xFFBDBDBD) : null,
        ),
      ),
    );
  }
}

class _CartImage extends StatelessWidget {
  final String? url;

  const _CartImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final normalized = url?.trim();

    if (normalized == null || normalized.isEmpty) {
      return Container(
        width: 78,
        height: 78,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF9CA3AF)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        normalized,
        width: 78,
        height: 78,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 78,
          height: 78,
          alignment: Alignment.center,
          color: const Color(0xFFF3F4F6),
          child: const Icon(Icons.broken_image_outlined),
        ),
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
