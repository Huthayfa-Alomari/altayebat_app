import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';
import '../screens/cart_screen.dart';
import '../theme/app_theme.dart';

class CartBar extends StatelessWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    if (cart.isEmpty) return const SizedBox.shrink();

    final total = cart.total;
    final itemCount = cart.itemCount;

    return SafeArea(
      top: false,
      child: Material(
        color: AppColors.surface,
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Semantics(
            button: true,
            label:
                'فتح السلة، $itemCount عنصر، المجموع ${total.toStringAsFixed(2)} دينار',
            child: SizedBox(
              height: 58,
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => CartScreen()));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Row(
                  children: [
                    _CartCountBadge(count: itemCount),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'عرض السلة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'المجموع',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${total.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartCountBadge extends StatelessWidget {
  final int count;

  const _CartCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.shopping_cart_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          PositionedDirectional(
            top: -8,
            end: -9,
            child: Container(
              constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
