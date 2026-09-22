import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../models/store_offer.dart';
import '../providers/cart_provider.dart';
import '../services/catalog_service.dart';
import '../services/growth_service.dart';
import '../services/store_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/altayebat_brand.dart';
import '../widgets/call_fab.dart';
import '../widgets/product_card.dart';
import '../widgets/social_contact_strip.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';

class HomeScreen extends StatefulWidget {
  final StorePublicSettings? settings;

  const HomeScreen({super.key, this.settings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _pageSize = CatalogService.defaultPageSize;

  StorePublicSettings get _settings =>
      widget.settings ?? StorePublicSettings.defaults();

  Color get _brandColor {
    final hex = _settings.primaryColor.replaceAll('#', '').trim();
    if (hex.length != 6) return AppColors.primary;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return AppColors.primary;
    return Color(0xFF000000 | value);
  }

  Widget _brandMark() => const AltayebatAppMark(size: 38);

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
      // Secondary content should never block shopping.
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
    _searchDebounce = Timer(const Duration(milliseconds: 420), () {
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
    final target = _scrollController.position.maxScrollExtent.clamp(0.0, 520.0);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
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
      floatingActionButton: _settings.featureCall ? const CallFab() : null,
    );
  }

  List<Widget> _buildSlivers() {
    final showDiscovery = _searchController.text.trim().isEmpty;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);

    return [
      if (_errorMessage != null) SliverToBoxAdapter(child: _errorState()),
      if (showDiscovery && _categories.isNotEmpty)
        SliverToBoxAdapter(child: _categoriesStrip()),
      if (showDiscovery && _activeSubcategories.isNotEmpty)
        SliverToBoxAdapter(child: _subcategoryStrip()),
      if (showDiscovery) SliverToBoxAdapter(child: _heroBanner()),
      if (showDiscovery && _categories.isNotEmpty)
        SliverToBoxAdapter(child: _categoryShowcase()),
      if (showDiscovery && _settings.featureReorder)
        SliverToBoxAdapter(child: _reorderCard()),
      if (showDiscovery && _settings.featureOffers && _offers.isNotEmpty)
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
            final columns = constraints.crossAxisExtent >= 600 ? 3 : 2;
            final baseHeight = columns == 3 ? 276.0 : 264.0;
            final adaptiveHeight = baseHeight + ((textScale - 1) * 76);

            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: adaptiveHeight,
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
      if (showDiscovery)
        SliverToBoxAdapter(child: SocialContactStrip(settings: _settings)),
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
              Semantics(
                button: true,
                label:
                    'السلة، ${cart.itemCount} عناصر، ${cart.total.toStringAsFixed(2)} دينار',
                child: InkWell(
                  onTap: _openCart,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Badge.count(
                          count: cart.itemCount,
                          isLabelVisible: cart.itemCount > 0,
                          backgroundColor: AppColors.primary,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: AppColors.skySoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              color: AppColors.navy,
                              size: 25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${cart.total.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _brandMark(),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            _settings.storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _brandColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      _settings.welcomeText,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
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
                semanticLabel: 'الإشعارات',
              ),
              const SizedBox(width: 7),
              _roundHeaderButton(
                icon: Icons.person_rounded,
                onTap: _openAccount,
                semanticLabel: 'حسابي',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
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
                  width: 62,
                  height: double.infinity,
                  child: Material(
                    color: AppColors.skyBlue,
                    borderRadius: BorderRadius.circular(19),
                    child: InkWell(
                      onTap: () => _reloadProducts(categoryId: null),
                      borderRadius: BorderRadius.circular(19),
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
                              tooltip: 'مسح البحث',
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
    required String semanticLabel,
    int badge = 0,
  }) {
    return Semantics(
      button: true,
      label: badge > 0 ? '$semanticLabel، $badge جديد' : semanticLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: AppColors.skySoft,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, color: AppColors.navy, size: 23),
              ),
            ),
          ),
          if (badge > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
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
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heroBanner() {
    final heroProducts = _products
        .where((product) => product.imageUrl?.trim().isNotEmpty == true)
        .take(3)
        .toList(growable: false);
    final offer = !_settings.featureOffers || _offers.isEmpty
        ? null
        : _offers.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Container(
        height: 184,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFEEF1), Colors.white, Color(0xFFEAF5FF)],
          ),
          border: Border.all(color: const Color(0xFFE8EEF5)),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              PositionedDirectional(
                end: -34,
                top: -36,
                child: Container(
                  width: 126,
                  height: 126,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              PositionedDirectional(
                start: -44,
                bottom: -52,
                child: Container(
                  width: 156,
                  height: 156,
                  decoration: BoxDecoration(
                    color: AppColors.skyBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              PositionedDirectional(
                start: 12,
                top: 18,
                bottom: 18,
                width: 132,
                child: _HeroProductCluster(products: heroProducts),
              ),
              PositionedDirectional(
                end: 16,
                top: 15,
                bottom: 15,
                start: 154,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        offer == null
                            ? 'تسوق أسرع من الطيبات'
                            : 'وفر ${offer.discountPercent}% اليوم',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'كل احتياجات البيت\nمرتبة وأسهل للوصول',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 19,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'أقسام واضحة • عروض يومية • طلب سريع',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        onPressed: _shopNow,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 12,
                        ),
                        label: const Text(
                          'تسوق الآن',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
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

  List<ProductCategory> get _rootCategories =>
      CatalogService.rootCategories(_categories);

  List<ProductCategory> get _activeSubcategories {
    final selectedId = _selectedCategoryId;
    if (selectedId == null) return const [];

    ProductCategory? selected;
    for (final category in _categories) {
      if (category.id == selectedId) {
        selected = category;
        break;
      }
    }
    if (selected == null) return const [];

    final parentId = selected.parentId ?? selected.id;
    return CatalogService.childrenOf(_categories, parentId);
  }

  Widget _categoriesStrip() {
    final rootCategories = _rootCategories;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'الأقسام',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _selectCategory(null),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.skyBlueDark,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'عرض الكل',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 106,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: rootCategories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final category = index == 0 ? null : rootCategories[index - 1];
                final selected = category == null
                    ? _selectedCategoryId == null
                    : category.id == _selectedCategoryId;
                final name = category?.name ?? 'الكل';

                return SizedBox(
                  width: 78,
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: name,
                    child: InkWell(
                      onTap: () => _selectCategory(category?.id),
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.skyBlue.withValues(alpha: 0.18),
                                width: selected ? 2 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ClipOval(
                              child: Container(
                                width: 64,
                                height: 64,
                                color: selected
                                    ? const Color(0xFFFFF2F4)
                                    : AppColors.skySoft,
                                child:
                                    category?.imageUrl?.trim().isNotEmpty ==
                                        true
                                    ? Image.network(
                                        category!.imageUrl!,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                        filterQuality: FilterQuality.medium,
                                        errorBuilder: (_, __, ___) => Icon(
                                          _categoryIcon(name),
                                          color: selected
                                              ? AppColors.primary
                                              : AppColors.navy,
                                          size: 30,
                                        ),
                                      )
                                    : Icon(
                                        _categoryIcon(name),
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.navy,
                                        size: 30,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontSize: 10.5,
                              height: 1.1,
                              fontWeight: selected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ],
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

  Widget _subcategoryStrip() {
    final items = _activeSubcategories;
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (context, index) {
            final category = items[index];
            final selected = category.id == _selectedCategoryId;
            return SizedBox(
              width: 92,
              child: Material(
                color: selected
                    ? const Color(0xFFFFF1F3)
                    : const Color(0xFFF4F8FC),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => _selectCategory(category.id),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                    child: Column(
                      children: [
                        Expanded(
                          child: _categoryMedia(
                            category: category,
                            name: category.name,
                            size: 50,
                            selected: selected,
                            compact: true,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
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

  Widget _categoryShowcase() {
    final visibleCategories = _rootCategories.take(14).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تسوق حسب القسم',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'مرر بين الأقسام واختر مباشرة',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.skySoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swipe_rounded,
                        color: AppColors.skyBlueDark,
                        size: 15,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'اسحب',
                        style: TextStyle(
                          color: AppColors.skyBlueDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 224,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: visibleCategories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 118,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final category = visibleCategories[index];
                final selected = category.id == _selectedCategoryId;
                final redTint = index.isEven;

                return Material(
                  color: redTint
                      ? const Color(0xFFFFF5F6)
                      : const Color(0xFFF2F8FF),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () => _selectCategory(category.id),
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : redTint
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : AppColors.skyBlue.withValues(alpha: 0.10),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: _categoryMedia(
                                category: category,
                                name: category.name,
                                size: 64,
                                selected: selected,
                                compact: false,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            category.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontSize: 10.7,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
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

  Widget _categoryMedia({
    required ProductCategory? category,
    required String name,
    required double size,
    required bool selected,
    required bool compact,
  }) {
    final imageUrl = category?.imageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final radius = compact ? 17.0 : 22.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.93, end: 1),
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        padding: EdgeInsets.all(compact ? 5 : 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFF0F2)
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.45)
                : Colors.white,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 5),
          child: hasImage
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Icon(
                    _categoryIcon(name),
                    color: selected ? AppColors.primary : AppColors.navy,
                    size: size * 0.48,
                  ),
                )
              : Icon(
                  _categoryIcon(name),
                  color: selected ? AppColors.primary : AppColors.navy,
                  size: size * 0.48,
                ),
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Material(
        color: const Color(0xFFE7F4FF),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _openOrders,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.skyBlueDark,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعادة طلب سابق بسرعة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'اطلب نفس المنتجات من طلبك الأخير',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (thumbnails.isNotEmpty) ...[
                  SizedBox(
                    width: 91,
                    height: 44,
                    child: Stack(
                      children: [
                        for (var index = 0; index < thumbnails.length; index++)
                          PositionedDirectional(
                            end: index * 25,
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
      padding: const EdgeInsets.only(bottom: 16),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Spacer(),
                Icon(
                  Icons.local_offer_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _offers.take(8).length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final offer = _offers[index];
                return SizedBox(
                  width: 198,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => _openOffer(offer),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFECEF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${offer.discountPercent}%',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
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
                                      fontSize: 12,
                                      height: 1.25,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${offer.offerPricePerUnit.toStringAsFixed(2)} د.أ',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 13,
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
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
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
          ),
          const SizedBox(width: 10),
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
        constraints: const BoxConstraints(minHeight: 108),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                mainAxisSize: MainAxisSize.min,
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
                  SizedBox(height: 5),
                  Text(
                    'اختيارات أسهل وتجربة تسوق أسرع من الطيبات',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF518560),
                      fontSize: 11.5,
                      height: 1.35,
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
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
        child: Text(_errorMessage ?? '', style: const TextStyle(fontSize: 12)),
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
          size: 68,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 146).clamp(0.84, 1.0);

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 126 * scale,
              height: 126 * scale,
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
                right:
                    (index == 0
                        ? 34
                        : index == 1
                        ? 3
                        : 69) *
                    scale,
                top:
                    (index == 0
                        ? 35
                        : index == 1
                        ? 76
                        : 80) *
                    scale,
                child: Transform.rotate(
                  angle: index == 1
                      ? 0.08
                      : index == 2
                      ? -0.07
                      : 0,
                  child: Container(
                    width: (index == 0 ? 76 : 63) * scale,
                    height: (index == 0 ? 94 : 74) * scale,
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
      },
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
