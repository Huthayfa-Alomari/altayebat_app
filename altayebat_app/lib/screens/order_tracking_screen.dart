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
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final status = snapshot.data!['status'] as String? ?? 'pending';
          final currentIndex = _statusOrder.indexOf(status);

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                for (int i = 0; i < _statusOrder.length; i++)
                  _stepTile(
                    label: _statusLabels[_statusOrder[i]]!,
                    done: i <= currentIndex,
                    isLast: i == _statusOrder.length - 1,
                  ),
                const Spacer(),
                if (status == 'out_for_delivery')
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.local_shipping_outlined,
                            color: AppColors.primary),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'المندوب بالطريق إلك، موقعه بيتحدث لحظياً',
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

  Widget _stepTile({
    required String label,
    required bool done,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? AppColors.primary : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: done ? AppColors.primary : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
              color: done ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}