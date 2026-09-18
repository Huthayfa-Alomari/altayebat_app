import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';
import '../services/store_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sponsored_ad_strip.dart';
import '../widgets/store_announcement_banner.dart';
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

class _StorefrontRootScreenState extends State<StorefrontRootScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  StorePublicSettings _settings = StorePublicSettings.defaults();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings(forceRefresh: true);
    }
  }

  Future<void> _loadSettings({bool forceRefresh = false}) async {
    final settings = await StoreSettingsService.load(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _openAiAssistant() async {
    if (!_settings.featureAi) return;
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
                children: [
                  HomeScreen(settings: _settings),
                  const OrderHistoryScreen(),
                  const CartScreen(),
                  const AccountScreen(),
                ],
              ),
            ),
            if (_index == 0) ...[
              StoreAnnouncementBanner(settings: _settings),
              if (_settings.storeStatus != 'open' ||
                  _settings.statusMessage.isNotEmpty)
                _StoreStatusStrip(settings: _settings),
              if (_settings.featureAds) const SponsoredAdStrip(),
            ],
          ],
        ),
        bottomNavigationBar: Selector<CartProvider, int>(
          selector: (_, cart) => cart.itemCount,
          builder: (context, cartCount, child) {
            final destinations = <NavigationDestination>[
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
              if (_settings.featureAi)
                const NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'المساعد',
                ),
            ];

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
                    if (_settings.featureAi && value == 4) {
                      _openAiAssistant();
                      return;
                    }
                    if (_index == value) return;
                    setState(() => _index = value);
                  },
                  height: 76,
                  elevation: 0,
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.primary.withValues(alpha: 0.10),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: destinations,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StoreStatusStrip extends StatelessWidget {
  final StorePublicSettings settings;

  const _StoreStatusStrip({required this.settings});

  @override
  Widget build(BuildContext context) {
    final label = switch (settings.storeStatus) {
      'busy' => 'المتجر مزدحم حاليًا',
      'temporarily_closed' => 'المتجر مغلق مؤقتًا',
      'maintenance' => 'المتجر تحت الصيانة',
      _ => 'تحديث من المتجر',
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: settings.storeStatus == 'busy'
            ? const Color(0xFFFFF4E5)
            : AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            settings.storeStatus == 'busy'
                ? Icons.schedule_rounded
                : Icons.info_outline_rounded,
            color: settings.storeStatus == 'busy'
                ? const Color(0xFF8A4B08)
                : AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              settings.statusMessage.isEmpty
                  ? label
                  : '$label — ${settings.statusMessage}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
