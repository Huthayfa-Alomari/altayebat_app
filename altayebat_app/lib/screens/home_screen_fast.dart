import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../models/store_offer.dart';
import '../providers/cart_provider.dart';
import '../services/catalog_service.dart';
import '../services/growth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _pageSize = CatalogService.defaultPageSize;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<ProductCategory> _categories = const [];
  List<Product> _products = const [];
  List<StoreOffer> _offers = const [];

  String? _selectedCategoryId;
  String? _errorMessage;
  bool _loading = true;
  bool _loadingProducts = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  int _requestGeneration = 0;
  int _secondaryGeneration = 0;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial({bool forceRefresh = false}) async {
    final generation = ++_requestGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      if (forceRefresh) CatalogService.invalidateAll();

      final results = await Future.wait<dynamic>([
        CatalogService.fetchCategories(forceRefresh: forceRefresh),
        CatalogService.fetchProductsPage(
          categoryId: _selectedCategoryId,
          searchQuery: _searchController.text,
          offset: 0,
          limit: _pageSize,
          forceRefresh: forceRefresh,
        ),
      ]);

      if (!mounted || generation != _requestGeneration) return;
      final page = results[1] as CatalogPage;
      setState(() {
        _categories = results[0] as List<ProductCategory>;
        _products = page.items;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingProducts = false;
        _loadingMore = false;
      });

      unawaited(_loadSecondary(forceRefresh: forceRefresh));
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loading = false;
        _loadingProducts = false;
        _loadingMore = false;
        _errorMessage =
            'تعذر تحميل المنتجات. تأكد من اتصال الإنترنت وحاول مرة ثانية.';
      });
    }
  }

  Future<void> _loadSecondary({bool forceRefresh = false}) async {
    final generation = ++_secondaryGeneration;
    try {
      final results = await Future.wait<dynamic>([
        GrowthService.fetchActiveOffers(forceRefresh: forceRefresh),
        GrowthService.unreadNotificationCount(forceRefresh: forceRefresh),
      ]);
      if (!mounted || generation != _secondaryGeneration) return;
      setState(() {
        _offers = results[0] as List<StoreOffer>;
        _unreadNotifications = results[1] as int;
      });
    } catch (_) {
      // Secondary content must never block shopping.
    }
  }

  Future<void> _reloadProducts({String? categoryId}) async {
    final generation = ++_requestGeneration;
    if (mounted) {
      setState(() {
        _selectedCategoryId = categoryId;
        _loadingProducts = true;
        _loadingMore = false;
        _hasMore = true;
        _nextOffset = 0;
        _errorMessage = null;
      });
    }

    try {
      final page = await CatalogService.fetchProductsPage(
        categoryId: categoryId,
        searchQuery: _searchController.text,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _products = page.items;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingProducts = false;
        _errorMessage = 'تعذر تحديث المنتجات. حاول مرة ثانية.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingProducts || _loadingMore || !_hasMore) return;
    final generation = _requestGeneration;
    setState(() => _loadingMore = true);

    try {
      final page = await CatalogService.fetchProductsPage(
        categoryId: _selectedCategoryId,
        searchQuery: _searchController.text,
        offset: _nextOffset,
        limit: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;

      final known = _products.map((product) => product.id).toSet();
      final additions = page.items
          .where((product) => known.add(product.id))
          .toList(growable: false);
      setState(() {
        _products = [..._products, ...additions];
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingMore = false;
        _errorMessage = 'تعذر تحميل المزيد. اسحب الصفحة وحاول مرة ثانية.';
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 700) _loadMore();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _reloadProducts(categoryId: null);
      return;
    }

    if (_selectedCategoryId != null && mounted) {
      setState(() => _selectedCategoryId = null);
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _reloadProducts(categoryId: null);
    });
  }

  Future<void> _clearSearch() async {
    _searchDebounce?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (mounted) setState(() {});
    await _reloadProducts(categoryId: null);
  }

  Future<void> _selectCategory(String? categoryId) async {
    _searchDebounce?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (mounted) setState(() {});
    await _reloadProducts(categoryId: categoryId);
  }

  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    final count = await GrowthService.unreadNotificationCount(
      forceRefresh: true,
    );
    if (mounted) setState(() => _unreadNotifications = count);
  }

  Future<void> _openOrders() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
  }

  Future<void> _openCart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  Future<void> _openAccount() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  Future<void> _openOffer(StoreOffer offer) async {
    if (offer.productName.trim().isEmpty) return;
    _searchController.text = offer.productName;
    if (mounted) setState(() => _selectedCategoryId = null);
    await _reloadProducts(categoryId: null);
  }

  Future<void> _refresh() async {
    GrowthService.invalidateStorefrontCaches();
    await _loadInitial(forceRefresh: true);
  }

  void _shopNow() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      430,
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: _buildSlivers(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSlivers() {
    final showDiscovery = _searchController.text.trim().isEmpty;
    return [
      if (_errorMessage != null) SliverToBoxAdapter(child: _errorState()),
      if (showDiscovery) SliverToBoxAdapter(child: _heroBanner()),
      if (showDiscovery && _categories.isNotEmpty)
        SliverToBoxAdapter(child: _categoriesStrip()),
      if (showDiscovery) SliverToBoxAdapter(child: _reorderCard()),
      if (showDiscovery && _offers.isNotEmpty)
        SliverToBoxAdapter(child: _offersStrip()),
      SliverToBoxAdapter(child: _resultsHeader()),
      if (_loadingProducts)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (_products.isEmpty)
        const SliverToBoxAdapter(child: _EmptyState())
      else
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.crossAxisExtent >= 520 ? 3 : 2;
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: columns == 3 ? 0.61 : 0.68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => RepaintBoundary(
                    child: ProductCard(product: _products[index]),
                  ),
                  childCount: _products.length,
                ),
              ),
            );
          },
        ),
      if (showDiscovery) SliverToBoxAdapter(child: _householdBanner()),
      SliverToBoxAdapter(child: _pagingFooter()),
      const SliverToBoxAdapter(child: SizedBox(height: 18)),
    ];
  }

  Widget _header() {
    final cart = context.watch<CartProvider>();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: _openCart,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Badge.count(
                        count: cart.itemCount,
                        isLabelVisible: cart.itemCount > 0,
                        backgroundColor: AppColors.primary,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.skySoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shopping_cart_outlined,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${cart.total.toStringAsFixed(2)} د.أ',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          color: AppColors.primary,
                          size: 31,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'أسواق الطيبات',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      'كل احتياجات البيت بمكان واحد',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _roundHeaderButton(
                icon: Icons.notifications_none_rounded,
                onTap: _openNotifications,
                badge: _unreadNotifications,
              ),
              const SizedBox(width: 7),
              _roundHeaderButton(
                icon: Icons.person_rounded,
                onTap: _openAccount,
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF18365A).withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  height: double.infinity,
                  child: Material(
                    color: AppColors.skyBlue,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => _reloadProducts(categoryId: null),
                      borderRadius: BorderRadius.circular(18),
                      child: const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 29,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _reloadProducts(categoryId: null),
                    onChanged: _onSearchChanged,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن منتج، علامة تجارية أو قسم...',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.skySoft,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, color: AppColors.navy, size: 22),
            ),
          ),
        ),
        if (badge > 0)
          PositionedDirectional(
            top: -4,
            end: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 19),
              height: 19,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white, width: 1.4),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _heroBanner() {
    final heroProducts = _products
        .where((product) => product.imageUrl?.trim().isNotEmpty == true)
        .take(3)
        .toList(growable: false);
    final offer = _offers.isEmpty ? null : _offers.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Container(
        height: 205,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFDFF1FF), Color(0xFFF5FBFF), Color(0xFFDDEEFF)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.skyBlue.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: -38,
              top: -42,
              child: Container(
                width: 145,
                height: 145,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.48),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: -34,
              bottom: -50,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: AppColors.skyBlue.withValues(alpha: 0.11),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 20,
              bottom: 17,
              width: 156,
              child: _HeroProductCluster(products: heroProducts),
            ),
            Positioned(
              left: 18,
              top: 25,
              bottom: 21,
              right: 174,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (offer != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'وفر ${offer.discountPercent}% اليوم',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'كل ما تحتاجه\nلبيتك في مكان واحد',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 23,
                      height: 1.16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'أسعار واضحة • منتجات مختارة • طلب أسهل',
                    maxLines: 2,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      onPressed: _shopNow,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14,
                      ),
                      label: const Text(
                        'تسوق الآن',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoriesStrip() {
    const colors = [
      Color(0xFFEAF4FF),
      Color(0xFFFFECEF),
      Color(0xFFEAF8EF),
      Color(0xFFFFF4DF),
      Color(0xFFF1ECFF),
      Color(0xFFE9F8F7),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: SizedBox(
        height: 102,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final category = index == 0 ? null : _categories[index - 1];
            final selected = category == null
                ? _selectedCategoryId == null
                : category.id == _selectedCategoryId;
            final name = category?.name ?? 'جميع الأقسام';
            final color = colors[index % colors.length];

            return SizedBox(
              width: 84,
              child: Material(
                color: selected ? AppColors.skySoft : color,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () => _selectCategory(category?.id),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? AppColors.skyBlue
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _categoryIcon(name),
                          color: selected
                              ? AppColors.skyBlueDark
                              : AppColors.navy,
                          size: 31,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 10,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
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
    );
  }

  IconData _categoryIcon(String name) {
    final value = name.toLowerCase();
    if (value.contains('منظف') || value.contains('منزل')) {
      return Icons.cleaning_services_rounded;
    }
    if (value.contains('حليب') ||
        value.contains('ألبان') ||
        value.contains('البان')) {
      return Icons.local_drink_rounded;
    }
    if (value.contains('طفل') || value.contains('أطفال')) {
      return Icons.child_friendly_rounded;
    }
    if (value.contains('لحم') || value.contains('دجاج')) {
      return Icons.restaurant_rounded;
    }
    if (value.contains('حلويات') || value.contains('مخبوز')) {
      return Icons.cake_rounded;
    }
    if (value.contains('مشروب')) return Icons.local_cafe_rounded;
    if (value.contains('قهوة')) return Icons.coffee_rounded;
    if (value.contains('مكسر')) return Icons.eco_rounded;
    if (value.contains('الكل') || value.contains('جميع')) {
      return Icons.grid_view_rounded;
    }
    return Icons.shopping_bag_rounded;
  }

  Widget _reorderCard() {
    final thumbnails = _products
        .where((product) => product.imageUrl?.trim().isNotEmpty == true)
        .take(3)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 15),
      child: Material(
        color: const Color(0xFFE7F4FF),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _openOrders,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.skyBlueDark,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعادة طلب سابق بسرعة',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'اطلب نفس المنتجات من طلبك الأخير',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (thumbnails.isNotEmpty) ...[
                  SizedBox(
                    width: 96,
                    height: 44,
                    child: Stack(
                      children: [
                        for (var index = 0; index < thumbnails.length; index++)
                          PositionedDirectional(
                            end: index * 27,
                            child: Container(
                              width: 43,
                              height: 43,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Image.network(
                                thumbnails[index].imageUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: AppColors.navy),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _offersStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(
                  'عروض اليوم',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Spacer(),
                Icon(
                  Icons.local_offer_rounded,
                  color: AppColors.primary,
                  size: 19,
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 94,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _offers.take(8).length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final offer = _offers[index];
                return SizedBox(
                  width: 190,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    child: InkWell(
                      onTap: () => _openOffer(offer),
                      borderRadius: BorderRadius.circular(17),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFECEF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${offer.discountPercent}%',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    offer.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${offer.offerPricePerUnit.toStringAsFixed(2)} د.أ',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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

  Widget _resultsHeader() {
    final query = _searchController.text.trim();
    final title = query.isNotEmpty
        ? 'نتائج البحث'
        : _selectedCategoryId == null
        ? 'منتجات مختارة لك'
        : _selectedCategoryName ?? 'المنتجات';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 11),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _selectedCategoryId == null
                ? null
                : () => _selectCategory(null),
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: Text(
              _selectedCategoryId == null
                  ? '${_products.length}${_hasMore ? '+' : ''} منتج'
                  : 'عرض الكل',
            ),
          ),
        ],
      ),
    );
  }

  String? get _selectedCategoryName {
    final id = _selectedCategoryId;
    if (id == null) return null;
    for (final category in _categories) {
      if (category.id == id) return category.name;
    }
    return null;
  }

  Widget _householdBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 2),
      child: Container(
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          gradient: const LinearGradient(
            colors: [Color(0xFFEAF8EF), Color(0xFFD8F2E2)],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_rounded,
                color: AppColors.success,
                size: 31,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'احتياجات البيت كل يوم',
                    style: TextStyle(
                      color: Color(0xFF20783A),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'اختيارات أسهل وتجربة تسوق أسرع من الطيبات',
                    style: TextStyle(
                      color: Color(0xFF518560),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF20783A),
              size: 17,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pagingFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (!_hasMore && _products.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            'وصلت لنهاية المنتجات',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _errorMessage ?? '',
          style: const TextStyle(fontSize: 11.5),
        ),
      ),
    );
  }
}

class _HeroProductCluster extends StatelessWidget {
  final List<Product> products;

  const _HeroProductCluster({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(
          Icons.local_mall_rounded,
          color: AppColors.skyBlue,
          size: 72,
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.skyBlue.withValues(alpha: 0.12),
                blurRadius: 22,
              ),
            ],
          ),
        ),
        for (var index = 0; index < products.length; index++)
          Positioned(
            right: index == 0
                ? 36
                : index == 1
                ? 4
                : 76,
            top: index == 0
                ? 36
                : index == 1
                ? 78
                : 83,
            child: Transform.rotate(
              angle: index == 1
                  ? 0.09
                  : index == 2
                  ? -0.08
                  : 0,
              child: Container(
                width: index == 0 ? 78 : 65,
                height: index == 0 ? 96 : 76,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.network(
                  products[index].imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 48, 24, 56),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 42,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'ما لقينا منتجات مطابقة',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
