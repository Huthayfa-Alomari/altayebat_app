import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'order_tracking_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _submitting = false;

  Future<void> _checkout(CartProvider cart) async {
    setState(() => _submitting = true);
    try {
      final items = cart.items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
                'unit_price': item.product.price,
              })
          .toList();

      final orderId = await SupabaseService.createOrder(
        items: items,
        total: cart.total,
      );

      cart.clear();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: orderId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('صار خطأ بإرسال الطلب، جرب مرة ثانية')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: cart.isEmpty
          ? const Center(child: Text('السلة فاضية'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: cart.items
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item.product.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      '${item.product.price.toStringAsFixed(2)} د.أ × ${item.quantity}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${item.subtotal.toStringAsFixed(2)} د.أ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المجموع'),
                        Text(
                          '${cart.total.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _submitting ? null : () => _checkout(cart),
                        child: Text(
                            _submitting ? 'جاري الإرسال...' : 'تأكيد الطلب'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}