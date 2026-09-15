import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/sponsored_ad_strip.dart';
import 'account_screen.dart';
import 'ai_shopping_assistant_screen.dart';
import 'cart_screen.dart';
import 'home_screen_v2.dart';
import 'order_history_screen.dart';

class StorefrontRootScreen extends StatefulWidget {
  const StorefrontRootScreen({super.key});

  @override
  State<StorefrontRootScreen> createState() => _StorefrontRootScreenState();
}

class _StorefrontRootScreenState extends State<StorefrontRootScreen> {
  int _index = 0;

  Future<void> _openAiAssistant() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiShoppingAssistantScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const [
                  HomeScreen(),
                  OrderHistoryScreen(),
                  CartScreen(),
                  AccountScreen(),
                ],
              ),
            ),
            if (_index == 0) const SponsoredAdStrip(),
          ],
        ),
        floatingActionButton: _index == 0
            ? FloatingActionButton.extended(
                onPressed: _openAiAssistant,
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text(
                  'اسأل الذكاء',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: Selector<CartProvider, int>(
          selector: (_, cart) => cart.itemCount,
          builder: (context, cartCount, child) {
            return DecoratedBox(
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
                  height: 76,
                  elevation: 0,
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.primary.withValues(alpha: 0.10),
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
            );
          },
        ),
      ),
    );
  }
}
