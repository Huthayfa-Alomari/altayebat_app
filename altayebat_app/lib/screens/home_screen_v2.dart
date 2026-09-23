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
import '../widgets/category_artwork.dart';
import 'categories_screen.dart';
import '../widgets/product_card.dart';
import '../widgets/social_contact_strip.dart';
import 'cart_screen.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';

class HomeScreen extends StatefulWidget {
  final StorePublicSettings? settings;
  final CatalogRepository repository;

  const HomeScreen({
    super.key,
    this.settings,
    this.repository = const CatalogRepository(),
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StorePublicSettings get _settings =>
      widget.settings ?? StorePublicSettings.defaults();

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
        widget.repository.categories(forceRefresh: forceRefresh),
        widget.repository.products(
          categoryId: _selectedCategoryId,
          searchQuery: _searchController.text,
          offset: 0,
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
      final page = await widget.repository.products(
        categoryId: categoryId,
        searchQuery: _searchController.text,
        offset: 0,
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
      final page = await widget.repository.products(
        categoryId: _selectedCategoryId,
        searchQuery: _searchController.text,
        offset: _nextOffset,
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
    if (categoryId != null) {
      final category = _categories.where((c) => c.id == categoryId).firstOrNull;
      if (category != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CategoryProductsScreen(
              category: category,
              categories: _categories,
              repository: widget.repository,
            ),
          ),
        );
        return;
      }
    }
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
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return [
      if (_errorMessage != null) SliverToBoxAdapter(child: _errorState()),
      if (showDiscovery && _categories.isNotEmpty)
        SliverToBoxAdapter(child: _categoriesStrip()),
      if (showDiscovery && _categories.isNotEmpty)
        SliverToBoxAdapter(child: _categoryShowcase()),
      if (showDiscovery) SliverToBoxAdapter(child: _heroBanner()),
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
            final columns = textScale > 1.6
                ? (constraints.crossAxisExtent >= 600 ? 2 : 1)
                : (constraints.crossAxisExtent >= 600 ? 3 : 2);
            final baseHeight = columns == 3 ? 276.0 : 264.0;
            final adaptiveHeight = baseHeight + ((textScale - 1) * 110);

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
    final count = context.select<CartProvider, int>((cart) => cart.itemCount);
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              _brandMark(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _settings.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _settings.welcomeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'الإشعارات',
                onPressed: _openNotifications,
                icon: Badge.count(
                  count: _unreadNotifications,
                  isLabelVisible: _unreadNotifications > 0,
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'السلة',
                onPressed: _openCart,
                icon: Badge.count(
                  count: count,
                  isLabelVisible: count > 0,
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              FocusScope.of(context).unfocus();
              _reloadProducts(categoryId: null);
            },
            onChanged: _onSearchChanged,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج أو علامة تجارية…',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.navy,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _clearSearch,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBanner() {
    final category = _rootCategories
        .where((c) => c.name == 'البقالة')
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Material(
        color: AppColors.skySoft,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: category == null
              ? _shopNow
              : () => _selectCategory(category.id),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مقاضي البيت',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'كل يوم، أقرب إلك',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'تسوق الأساسيات  ←',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (category != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: CategoryArtwork(category: category, size: 114),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ProductCategory> get _rootCategories =>
      CatalogService.rootCategories(_categories);

  Widget _categoriesStrip() {
    const icons = [
      Icons.restaurant_outlined,
      Icons.egg_outlined,
      Icons.kitchen_outlined,
      Icons.cookie_outlined,
      Icons.local_cafe_outlined,
      Icons.ac_unit_rounded,
      Icons.cleaning_services_outlined,
      Icons.spa_outlined,
    ];
    final categories = _rootCategories;
    return Material(
      color: AppColors.navy,
      child: SizedBox(
        height:
            74 +
            (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 3) * 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: categories.length + 1,
          separatorBuilder: (_, i) => const SizedBox(width: 4),
          itemBuilder: (_, i) => Semantics(
            button: true,
            selected: i == 0,
            child: InkWell(
              onTap: () =>
                  _selectCategory(i == 0 ? null : categories[i - 1].id),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: i == 0 ? 52 : 92,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      i == 0
                          ? Icons.grid_view_rounded
                          : icons[(i - 1) % icons.length],
                      color: Colors.white,
                      size: 25,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      i == 0 ? 'الكل' : categories[i - 1].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 3,
                      width: 28,
                      color: i == 0 ? AppColors.primary : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryShowcase() {
    final categories = _rootCategories;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'تسوق حسب القسم',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CategoriesScreen(repository: widget.repository),
                  ),
                ),
                child: const Text(
                  'كل الأقسام',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = scale > 1.5
                  ? 2
                  : constraints.maxWidth >= 600
                  ? 6
                  : 4;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  mainAxisExtent: width + 54 + (scale - 1).clamp(0, 3) * 42,
                ),
                itemBuilder: (_, i) => CategoryTile(
                  category: categories[i],
                  compact: true,
                  onTap: () => _selectCategory(categories[i].id),
                ),
              );
            },
          ),
        ],
      ),
    );
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
