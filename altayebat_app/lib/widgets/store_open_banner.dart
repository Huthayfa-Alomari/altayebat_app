import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class StoreOpenBanner extends StatelessWidget {
  const StoreOpenBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: SupabaseService.getStoreOpenState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final state = snapshot.data;
        if (state == null) return const SizedBox.shrink();

        final open = state['open'] == true;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: open ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                open ? Icons.storefront : Icons.storefront_outlined,
                size: 20,
                color: open ? const Color(0xFF166534) : const Color(0xFF9F1239),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  open ? 'المتجر يستقبل الطلبات الآن' : 'الطلبات متوقفة حاليًا',
                  style: TextStyle(
                    color: open
                        ? const Color(0xFF166534)
                        : const Color(0xFF9F1239),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
