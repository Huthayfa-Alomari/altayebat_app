import 'dart:async';

import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../models/store_offer.dart';
import '../services/growth_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/call_fab.dart';
import '../widgets/cart_bar.dart';
import '../widgets/product_card.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<ProductCategory> _categories = const [];
  List<Product> _products = const [];
  List<StoreOffer> _offers = const [];
  String? _selectedCategoryId;
  String? _errorMessage;
  bool _loading = true;
  bool _loadingProducts = false;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.fetchCategories(),
        SupabaseService.fetchProducts(
          categoryId: _selectedCategoryId,
          searchQuery: _searchController.text,
        ),
        GrowthService.fetchActiveOffers(),
        GrowthService.unreadNotificationCount(),
      ]);

      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<ProductCategory>;
        _products = results[1] as List<Product>;
        _offers = results[2] as List<StoreOffer>;
        _unreadNotifications = results[3] as int;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'تعذر تحميل المنتجات. تأكد من اتصال الإنترنت وحاول مرة ثانية.';
      });
    }
  }

  Future<void> _loadProducts({String? categoryId}) async {
    if (mounted) {
      setState(() {
        _selectedCategoryId = categoryId;
        _loadingProducts = true;
        _errorMessage = null;
      });
    }

    try {
      final products = await SupabaseService.fetchProducts(
        categoryId: categoryId,
        searchQuery: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
        _errorMessage = 'تعذر تحديث المنتجات. حاول مرة ثانية.';
      });
    }
  }

  Future<void> _search() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isNotEmpty && mounted) {
      setState(() => _selectedCategoryId = null);
    }
    await _loadProducts(categoryId: query.isEmpty ? _selectedCategoryId : null);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (mounted && query.isNotEmpty) {
      setState(() => _selectedCategoryId = null);
    }

    if (query.isEmpty) {
      _loadProducts(categoryId: null);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadProducts(categoryId: null);
    });
  }

  Future<void> _clearSearch() async {
    _searchDebounce?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (mounted) setState(() {});
    await _loadProducts(categoryId: null);
  }

  Future<void> _selectCategory(String? categoryId) async {
    _searchDebounce?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (mounted) setState(() {});
    await _loadProducts(categoryId: categoryId);
  }

  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    final count = await GrowthService.unreadNotificationCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }

  Future<void> _openOrders() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
  }

  Future<void> _openOffer(StoreOffer offer) async {
    if (offer.productName.trim().isEmpty) return;
    _selectedCategoryId = null;
    _searchController.text = offer.productName;
    if (mounted) setState(() {});
    await _loadProducts(categoryId: null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8),
                        children: [
                          if (_errorMessage != null) _errorState(),
                          if (_searchController.text.trim().isEmpty) ...[
                            _quickActions(),
                            if (_offers.isNotEmpty) _offersSection(),
                            _categoryChips(),
                          ],
                          _resultsHeader(),
                          if (_loadingProducts)
                            const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          else
                            _productGrid(),
                        ],
                      ),
                    ),
            ),
            const CartBar(),
          ],
        ),
      ),
      floatingActionButton: const CallFab(),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أسواق الطيبات',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'تسوّق بسهولة ووصل طلبك لباب البيت',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'الإشعارات',
                    onPressed: _openNotifications,
                    color: Colors.white,
                    icon: const Icon(Icons.notifications_none),
                  ),
                  if (_unreadNotifications > 0)
                    PositionedDirectional(
                      top: 2,
                      end: 1,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          _unreadNotifications > 99
                              ? '99+'
                              : '$_unreadNotifications',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'شو بدك؟ ابحث باسم المنتج',
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: AppColors.textSecondary,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close, size: 18),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.replay_outlined,
              title: 'إعادة الطلب',
              subtitle: 'من طلباتك السابقة',
              onTap: _openOrders,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.local_offer_outlined,
              title: 'العروض',
              subtitle: _offers.isEmpty
                  ? 'قريباً عروض جديدة'
                  : '${_offers.length} عرض متوفر',
              onTap: () {
                if (_offers.isNotEmpty) {
                  Scrollable.ensureVisible(
                    context,
                    duration: const Duration(milliseconds: 250),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _offersSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'عروض اليوم',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 142,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _offers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final offer = _offers[index];
                return SizedBox(
                  width: 250,
                  child: Material(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _openOffer(offer),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEA580C),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'خصم ${offer.discountPercent}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.local_offer,
                                  color: Color(0xFFEA580C),
                                  size: 20,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              offer.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            if ((offer.subtitle ?? '').trim().isNotEmpty)
                              Text(
                                offer.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 11,
                                ),
                              ),
                            const Spacer(),
                            Row(
                              children: [
                                Text(
                                  '${offer.offerPricePerUnit.toStringAsFixed(2)} د.أ',
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  offer.regularPricePerUnit.toStringAsFixed(2),
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'الأقسام',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 7),
                  child: ChoiceChip(
                    label: const Text('الكل'),
                    selected: _selectedCategoryId == null,
                    onSelected: (_) => _selectCategory(null),
                  ),
                ),
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 7),
                    child: ChoiceChip(
                      avatar: Icon(
                        Icons.category_outlined,
                        size: 16,
                        color: _selectedCategoryId == category.id
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                      label: Text(category.name),
                      selected: _selectedCategoryId == category.id,
                      onSelected: (_) => _selectCategory(category.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.red.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                ),
              ),
              TextButton(onPressed: _load, child: const Text('إعادة')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultsHeader() {
    final query = _searchController.text.trim();
    ProductCategory? selected;
    for (final category in _categories) {
      if (category.id == _selectedCategoryId) {
        selected = category;
        break;
      }
    }

    final title = query.isNotEmpty
        ? 'نتائج البحث'
        : selected?.name ?? 'كل المنتجات';
    final countText = _loadingProducts
        ? 'جاري التحميل...'
        : '${_products.length} منتج';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  query.isNotEmpty ? '“$query” • $countText' : countText,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (query.isNotEmpty)
            TextButton(onPressed: _clearSearch, child: const Text('مسح')),
        ],
      ),
    );
  }

  Widget _productGrid() {
    if (_products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 44, 24, 56),
        child: Column(
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 44,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _searchController.text.trim().isNotEmpty
                  ? 'ما لقينا المنتج'
                  : 'ما في منتجات متوفرة حاليًا',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 540
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          itemCount: _products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 0.60 : 0.68,
          ),
          itemBuilder: (context, index) =>
              ProductCard(product: _products[index]),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
