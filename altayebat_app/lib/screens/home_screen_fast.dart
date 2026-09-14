import 'dart:async';

import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../models/store_offer.dart';
import '../services/catalog_service.dart';
import '../services/growth_service.dart';
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

      // Only data required to paint the storefront blocks the first content
      // frame. Offers and notification count are secondary and load immediately
      // after the catalog is visible.
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
      // Offers and notification badges are enhancements. A temporary failure
      // must never block browsing the catalogue or using the cart.
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
    if (_scrollController.position.extentAfter < 700) {
      _loadMore();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
            const CartBar(),
          ],
        ),
      ),
      floatingActionButton: const CallFab(),
    );
  }

  List<Widget> _buildSlivers() {
    final showDiscovery = _searchController.text.trim().isEmpty;
    return [
      if (_errorMessage != null) SliverToBoxAdapter(child: _errorState()),
      if (showDiscovery && _categories.isNotEmpty)
        SliverToBoxAdapter(child: _categoriesStrip()),
      if (showDiscovery && _offers.isNotEmpty)
        SliverToBoxAdapter(child: _offersStrip()),
      if (showDiscovery) SliverToBoxAdapter(child: _reorderCard()),
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
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.66,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => RepaintBoundary(
                child: ProductCard(product: _products[index]),
              ),
              childCount: _products.length,
            ),
          ),
        ),
      SliverToBoxAdapter(child: _pagingFooter()),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.skySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أسواق الطيبات',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'كل احتياجات البيت بمكان واحد',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton.filledTonal(
                    onPressed: _openNotifications,
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  if (_unreadNotifications > 0)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
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
            onSubmitted: (_) => _reloadProducts(categoryId: null),
            onChanged: _onSearchChanged,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.skyBlueDark,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: AppColors.softSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(
                  color: AppColors.skyBlue,
                  width: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoriesStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تسوّق حسب القسم',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = index == 0 ? null : _categories[index - 1];
                final selected = category == null
                    ? _selectedCategoryId == null
                    : category.id == _selectedCategoryId;
                return ChoiceChip(
                  selected: selected,
                  onSelected: (_) => _selectCategory(category?.id),
                  label: Text(category?.name ?? 'الكل'),
                  avatar: category == null
                      ? const Icon(Icons.grid_view_rounded, size: 16)
                      : null,
                  selectedColor: AppColors.skySoft,
                  side: BorderSide(
                    color: selected ? AppColors.skyBlue : AppColors.border,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _offersStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 118,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: _offers.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final offer = _offers[index];
            return SizedBox(
              width: 230,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                child: InkWell(
                  onTap: () => _openOffer(offer),
                  borderRadius: BorderRadius.circular(17),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0xFFF1DEDE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'خصم ${offer.discountPercent}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.local_offer_rounded,
                              color: AppColors.skyBlueDark,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          offer.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        Text(
                          '${offer.offerPricePerUnit.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 15,
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

  Widget _reorderCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Material(
        color: AppColors.skySoft,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _openOrders,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: AppColors.skyBlueDark),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'كرّر طلب سابق بسرعة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Icon(Icons.chevron_left_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultsHeader() {
    final query = _searchController.text.trim();
    final title = query.isNotEmpty
        ? 'نتائج البحث'
        : _selectedCategoryId == null
        ? 'كل المنتجات'
        : _selectedCategoryName ?? 'المنتجات';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '${_products.length}${_hasMore ? '+' : ''}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
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
