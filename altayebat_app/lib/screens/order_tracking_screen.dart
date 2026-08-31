import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/call_fab.dart';

const Map<String, String> _statusLabels = {
  'pending': 'بانتظار تأكيد المول',
  'preparing': 'قيد التحضير',
  'out_for_delivery': 'بالتوصيل إلك',
  'delivered': 'تم التسليم',
  'cancelled': 'ملغي',
};

const List<String> _statusOrder = [
  'pending',
  'preparing',
  'out_for_delivery',
  'delivered',
];

class OrderTrackingScreen extends StatelessWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: SupabaseService.watchOrder(orderId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _messageState(
              icon: Icons.cloud_off_outlined,
              title: 'تعذر تحديث الطلب',
              subtitle: 'تأكد من الإنترنت وافتح الشاشة مرة ثانية.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _messageState(
              icon: Icons.receipt_long_outlined,
              title: 'الطلب غير متاح',
              subtitle: 'قد يكون الطلب غير موجود أو غير مرتبط بحسابك.',
            );
          }

          final status = snapshot.data!['status'] as String? ?? 'pending';
          if (status == 'cancelled') {
            return _cancelledState();
          }

          final currentIndex = _statusOrder.indexOf(status);
          final safeIndex = currentIndex < 0 ? 0 : currentIndex;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'رقم الطلب',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              _shortOrderId(orderId),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _statusLabels[status] ?? status,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                for (int i = 0; i < _statusOrder.length; i++)
                  _stepTile(
                    label: _statusLabels[_statusOrder[i]]!,
                    done: i <= safeIndex,
                    active: i == safeIndex,
                    isLast: i == _statusOrder.length - 1,
                  ),
                const Spacer(),
                if (status == 'out_for_delivery')
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'المندوب بالطريق إلك. إذا احتجت مساعدة استخدم زر التواصل.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (status == 'delivered')
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'تم تسليم طلبك. صحتين وعافية!',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: CallFab(orderId: orderId),
    );
  }

  Widget _cancelledState() {
    return _messageState(
      icon: Icons.cancel_outlined,
      title: 'تم إلغاء الطلب',
      subtitle: 'إذا عندك استفسار عن الإلغاء، استخدم زر التواصل مع الموظف.',
      iconColor: Colors.redAccent,
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String subtitle,
    Color iconColor = AppColors.textSecondary,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepTile({
    required String label,
    required bool done,
    required bool active,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: done ? AppColors.primary : AppColors.border,
                shape: BoxShape.circle,
                border: active
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 38,
                color: done ? AppColors.primary : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: done ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _shortOrderId(String id) {
    if (id.length <= 10) return id;
    return '#${id.substring(0, 8).toUpperCase()}';
  }
}
