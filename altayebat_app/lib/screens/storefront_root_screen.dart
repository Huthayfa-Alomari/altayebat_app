import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';
import '../theme/app_theme.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'home_screen_fast.dart';
import 'order_history_screen.dart';

class StorefrontRootScreen extends StatefulWidget {
  const StorefrontRootScreen({super.key});

  @override
  State<StorefrontRootScreen> createState() => _StorefrontRootScreenState();
}

class _StorefrontRootScreenState extends State<StorefrontRootScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartProvider>().itemCount;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            OrderHistoryScreen(),
            CartScreen(),
            AccountScreen(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF11213B).withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) {
                if (_index == value) return;
                setState(() => _index = value);
              },
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'الرئيسية',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'طلباتي',
                ),
                NavigationDestination(
                  icon: Badge.count(
                    count: cartCount,
                    isLabelVisible: cartCount > 0,
                    backgroundColor: AppColors.primary,
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  selectedIcon: Badge.count(
                    count: cartCount,
                    isLabelVisible: cartCount > 0,
                    backgroundColor: AppColors.primary,
                    child: const Icon(Icons.shopping_cart_rounded),
                  ),
                  label: 'السلة',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'حسابي',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
