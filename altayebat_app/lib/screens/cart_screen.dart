import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
  String _paymentMethod = 'cash';

  Future<void> _checkout(CartProvider cart) async {
    if (_submitting || cart.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final items = cart.items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
              })
          .toList();

      final orderId = await SupabaseService.createOrder(
        items: items,
        paymentMethod: _paymentMethod,
      );

      if (_paymentMethod == 'card') {
        final paymentUrl = await SupabaseService.startCardPayment(orderId);
        final launched = await launchUrl(
          Uri.parse(paymentUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw StateError('تعذر فتح صفحة الدفع بالبطاقة');
        }
      }

      cart.clear();
      if (!mounted) return;

      if (_paymentMethod == 'cliq') {
        final config = await SupabaseService.getStorePaymentConfig();
        if (!mounted) return;
        final alias = config['cliq_alias'] as String?;
        final recipient = config['cliq_recipient_name'] as String?;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('الدفع عبر CliQ'),
            content: Text(
              alias == null || alias.trim().isEmpty
                  ? 'تم تسجيل الطلب كدفع عبر CliQ. سيؤكد المول عملية التحويل بعد التواصل معك.'
                  : 'حوّل قيمة الطلب إلى CliQ: $alias${recipient == null || recipient.isEmpty ? '' : '\nالاسم: $recipient'}\nثم انتظر تأكيد المول للدفع.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تم'),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: orderId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is StateError
          ? e.message
          : 'صار خطأ بإرسال الطلب، جرب مرة ثانية';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _paymentOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _paymentMethod == value;
    return InkWell(
      onTap: _submitting ? null : () => setState(() => _paymentMethod = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: _paymentMethod,
              onChanged: _submitting
                  ? null
                  : (v) {
                      if (v != null) setState(() => _paymentMethod = v);
                    },
            ),
            Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
              children: [
                ...cart.items.map((item) {
                  final canAdd = cart.canAdd(item.product);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item.product.price.toStringAsFixed(2)} د.أ للحبة',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: _submitting
                                            ? null
                                            : () => cart.decrement(item.product),
                                        icon: const Icon(Icons.remove_circle_outline),
                                      ),
                                      Text('${item.quantity}'),
                                      IconButton(
                                        onPressed: _submitting || !canAdd
                                            ? null
                                            : () => cart.add(item.product),
                                        icon: const Icon(Icons.add_circle_outline),
                                      ),
                                      TextButton(
                                        onPressed: _submitting
                                            ? null
                                            : () => cart.remove(item.product.id),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${item.subtotal.toStringAsFixed(2)} د.أ',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                const Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.w700)),
                _paymentOption(
                  value: 'cash',
                  title: 'كاش عند الاستلام',
                  subtitle: 'ادفع للمندوب عند وصول الطلب',
                  icon: Icons.payments_outlined,
                ),
                _paymentOption(
                  value: 'cliq',
                  title: 'CliQ',
                  subtitle: 'تحويل فوري ويؤكد المول وصول الدفعة',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                _paymentOption(
                  value: 'card',
                  title: 'Visa / Mastercard',
                  subtitle: 'دفع إلكتروني آمن عبر بوابة PayTabs',
                  icon: Icons.credit_card,
                ),
                const SizedBox(height: 120),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المجموع (${cart.itemCount} قطعة)'),
                        Text(
                          '${cart.total.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : () => _checkout(cart),
                        child: Text(
                          _submitting
                              ? 'جاري الإرسال...'
                              : _paymentMethod == 'card'
                                  ? 'المتابعة للدفع'
                                  : 'تأكيد الطلب',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
