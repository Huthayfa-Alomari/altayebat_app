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
        GrowthService.fetchActiveOffers(forceRefresh: forceRefresh),
        GrowthService.unreadNotificationCount(forceRefresh: forceRefresh),
      ]);

      if (!mounted || generation != _requestGeneration) return;
      final page = results[1] as CatalogPage;
      setState(() {
        _categories = results[0] as List<ProductCategory>;
        _products = page.items;
        _offers = results[2] as List<StoreOffer>;
        _unreadNotifications = results[3] as int;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingProducts = false;
        _loadingMore = false;
      });
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

  Future<void> _reloadProducts({
    String? categoryId,
    bool forceRefresh = false,
  }) async {
    final generation = ++_requestGeneration;
    if (mounted) {
      setState(() {
        _selectedCategoryId = categoryId;
        _loadingProducts = true;
        _loadingMore = false;
        _errorMessage = null;
        _hasMore = true;
        _nextOffset = 0;
      });
    }

    try {
      final page = await CatalogService.fetchProductsPage(
        categoryId: categoryId,
        searchQuery: _searchController.text,
        offset: 0,
        limit: _pageSize,
        forceRefresh: forceRefresh,
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
    final position = _scrollController.position;
    if (position.extentAfter < 700) {
      _loadMore();
    }
  }

  Future<void> _search() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isNotEmpty && mounted) {
      setState(() => _selectedCategoryId = null);
    }
    await _reloadProducts(
      categoryId: query.isEmpty ? _selectedCategoryId : null,
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      _reloadProducts(categoryId: null);
      return;
    }

    if (mounted && _selectedCategoryId != null) {
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
    final count = await GrowthService.unreadNotificationCount(forceRefresh: true);
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
                      child: ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        children: [
                          if (_errorMessage != null) _errorState(),
                          if (_searchController.text.trim().isEmpty) ...[
                            _categorySection(),
                            if (_offers.isNotEmpty) _offersSection(),
                            _reorderCard(),
                          ],
                          _resultsHeader(),
                          if (_loadingProducts)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            _productGrid(),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                ),
                              ),
                            )
                          else if (!_hasMore && _products.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 12),
                              child: Center(
                                child: Text(
                                  'وصلت لنهاية المنتجات',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
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
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'كل احتياجات البيت بمكان واحد',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: AppColors.softSurface,
                    borderRadius: BorderRadius.circular(13),
                    child: IconButton(
                      tooltip: 'الإشعارات',
                      onPressed: _openNotifications,
                      color: AppColors.textPrimary,
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                  ),
                  if (_unreadNotifications > 0)
                    PositionedDirectional(
                      top: -2,
                      end: -3,
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
            onSubmitted: (_) => _search(),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج...',
              hintStyle: const TextStyle(
                color: Color(0xFF979797),
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 21,
                color: AppColors.skyBlueDark,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: AppColors.softSurface,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
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

  Widget _categorySection() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    final featured = _featuredCategories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تسوّق حسب القسم',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'اختَر القسم ووصل لمنتجاتك بسرعة',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (_categories.length > 8)
                TextButton.icon(
                  onPressed: _openAllCategories,
                  icon: const Icon(Icons.grid_view_rounded, size: 16),
                  label: const Text('عرض الكل'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.skyBlueDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 650 ? 4 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: featured.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 96,
                ),
                itemBuilder: (context, index) {
                  final category = featured[index];
                  return _CategoryTile(
                    emoji: _categoryEmoji(category.name),
                    label: category.name,
                    selected: _selectedCategoryId == category.id,
                    onTap: () => _selectCategory(category.id),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  List<ProductCategory> get _featuredCategories {
    final categories = List<ProductCategory>.of(_categories);
    categories.sort((a, b) {
      final aRank = _categoryPriority(a.name);
      final bRank = _categoryPriority(b.name);
      if (aRank != bRank) return aRank.compareTo(bRank);
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.name.compareTo(b.name);
    });
    return categories.take(8).toList(growable: false);
  }

  int _categoryPriority(String name) {
    final value = name.toLowerCase().trim();
    if (value.contains('مكسر') || value.contains('nuts')) return 0;
    if (value.contains('قهو') || value.contains('coffee')) return 1;
    if (_isDairy(value)) return 2;
    if (value.contains('بقول') || value.contains('عدس')) return 3;
    if (_isGrain(value)) return 4;
    if (value.contains('مخلل')) return 5;
    if (value.contains('مشروب') || value.contains('عصير')) return 6;
    if (value.contains('منظف') || value.contains('تنظيف')) return 7;
    return 100;
  }

  Future<void> _openAllCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'كل الأقسام',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: _categories.length + 1,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 96,
                        ),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _CategoryTile(
                          emoji: '🛒',
                          label: 'كل المنتجات',
                          selected: _selectedCategoryId == null,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _selectCategory(null);
                          },
                        );
                      }

                      final category = _categories[index - 1];
                      return _CategoryTile(
                        emoji: _categoryEmoji(category.name),
                        label: category.name,
                        selected: _selectedCategoryId == category.id,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _selectCategory(category.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _offersSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'عروض اليوم',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.local_offer_outlined,
                  color: AppColors.primary,
                  size: 21,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _offers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final offer = _offers[index];
                return SizedBox(
                  width: 238,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () => _openOffer(offer),
                      child: Container(
                        padding: const EdgeInsets.all(13),
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
                                    vertical: 4,
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
                            const SizedBox(height: 9),
                            Text(
                              offer.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if ((offer.subtitle ?? '').trim().isNotEmpty)
                              Text(
                                offer.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10.5,
                                ),
                              ),
                            const Spacer(),
                            Row(
                              children: [
                                Text(
                                  '${offer.offerPricePerUnit.toStringAsFixed(2)} د.أ',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  offer.regularPricePerUnit.toStringAsFixed(2),
                                  style: const TextStyle(
                                    color: Color(0xFF9A9A9A),
                                    fontSize: 10.5,
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

  Widget _reorderCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Material(
        color: AppColors.skySoft,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: _openOrders,
          borderRadius: BorderRadius.circular(18),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: AppColors.skyBlueDark),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كرّر طلب سابق بسرعة',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'افتح طلباتك السابقة وأعد المنتجات المتوفرة للسلة',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded, color: AppColors.skyBlueDark),
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
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
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
              fontWeight: FontWeight.w700,
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

  Widget _productGrid() {
    if (_products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 44, 24, 56),
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
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 620
              ? 3
              : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _products.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: columns == 2 ? 0.66 : 0.72,
            ),
            itemBuilder: (context, index) => RepaintBoundary(
              child: ProductCard(product: _products[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD4D4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _errorMessage ?? '',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isDairy(String value) {
    return value.contains('ألبان') ||
        value.contains('البان') ||
        value.contains('حليب') ||
        value.contains('لبن') ||
        value.contains('جبن') ||
        value.contains('dairy');
  }

  bool _isGrain(String value) {
    return value.contains('أرز') ||
        value.contains('ارز') ||
        value.contains('حبوب') ||
        value.contains('طحين') ||
        value.contains('رز');
  }

  String _categoryEmoji(String name) {
    final value = name.toLowerCase();
    if (value.contains('مكسر')) return '🥜';
    if (value.contains('قهو')) return '☕';
    if (_isDairy(value)) return '🥛';
    if (value.contains('بقول') || value.contains('عدس')) return '🫘';
    if (_isGrain(value)) return '🌾';
    if (value.contains('مخلل')) return '🥒';
    if (value.contains('مشروب') || value.contains('عصير')) return '🧃';
    if (value.contains('منظف')) return '🧼';
    if (value.contains('مجمد')) return '❄️';
    if (value.contains('معلب')) return '🥫';
    if (value.contains('طفل') || value.contains('أطفال')) return '👶';
    if (value.contains('حيوان') || value.contains('قطط')) return '🐾';
    if (value.contains('خبز') || value.contains('مخبوز')) return '🥖';
    if (value.contains('شوكولا') || value.contains('حلويات')) return '🍫';
    return '🛍️';
  }
}

class _CategoryTile extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.skySoft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.skyBlue : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? AppColors.skyBlueDark
                      : AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
