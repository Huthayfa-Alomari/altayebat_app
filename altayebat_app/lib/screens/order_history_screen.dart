import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../services/growth_service.dart';
import '../theme/app_theme.dart';
import 'cart_screen.dart';
import 'order_tracking_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _busyOrderId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final orders = await GrowthService.fetchMyOrders();
      if (!mounted) return;
      setState(() => _orders = orders);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل طلباتك السابقة');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'pending':
        return 'بانتظار التأكيد';
      case 'preparing':
        return 'قيد التجهيز';
      case 'out_for_delivery':
        return 'بالتوصيل';
      case 'delivered':
        return 'تم التسليم';
      case 'cancelled':
        return 'ملغي';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'pending':
        return const Color(0xFFE58A00);
      case 'preparing':
        return AppColors.skyBlueDark;
      case 'out_for_delivery':
        return const Color(0xFF6D4BD1);
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _date(dynamic raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (value == null) return '—';
    return DateFormat('dd/MM/yyyy • HH:mm').format(value);
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _reorder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    if (orderId.isEmpty || _busyOrderId != null) return;

    final cart = context.read<CartProvider>();
    if (!cart.isEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('استبدال السلة الحالية؟'),
          content: const Text(
            'إعادة الطلب ستضع المنتجات المتوفرة من الطلب السابق بدل محتويات السلة الحالية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استبدال وإعادة الطلب'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    setState(() => _busyOrderId = orderId);
    try {
      final result = await GrowthService.buildReorder(orderId);
      if (!mounted) return;

      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('منتجات هذا الطلب غير متوفرة حاليًا')),
        );
        return;
      }

      cart.replaceAll(
        result.lines.map(
          (line) => CartItem(product: line.product, quantity: line.quantity),
        ),
      );

      final notes = <String>[];
      if (result.unavailableCount > 0) {
        notes.add('${result.unavailableCount} صنف غير متوفر لم يُضف');
      }
      if (result.adjustedCount > 0) {
        notes.add('${result.adjustedCount} كمية عُدلت حسب المخزون الحالي');
      }

      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CartScreen()));

      if (mounted && notes.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notes.join(' • '))));
      }
    } catch (error) {
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('طلباتي'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _orders.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 100),
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: AppColors.skySoft,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.skyBlue.withValues(alpha: 0.16),
                            ),
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            size: 44,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error ?? 'أول طلب إلك راح يظهر هون',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        final id = order['id']?.toString() ?? '';
                        final shortId = id.replaceAll('-', '');
                        final displayId = shortId
                            .substring(
                              0,
                              shortId.length >= 8 ? 8 : shortId.length,
                            )
                            .toUpperCase();
                        final busy = _busyOrderId == id;

                        final status =
                            order['status']?.toString() ?? '';
                        final statusColor = _statusColor(status);

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.navy.withValues(alpha: 0.04),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '#$displayId',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(
                                          alpha: 0.09,
                                        ),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        _statusLabel(status),
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _date(order['created_at']),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: AppColors.skySoft,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.shopping_bag_outlined,
                                        color: AppColors.skyBlueDark,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        '${_number(order['total']).toStringAsFixed(2)} د.أ',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: id.isEmpty
                                            ? null
                                            : () => Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      OrderTrackingScreen(
                                                        orderId: id,
                                                      ),
                                                ),
                                              ),
                                        child: const Text('التفاصيل'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _reorder(order),
                                        icon: busy
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.replay_outlined),
                                        label: const Text('إعادة الطلب'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
