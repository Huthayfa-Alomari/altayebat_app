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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
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
                  color: AppColors.primary.withValues(alpha: 0.08),
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
                color: AppColors.textSecondary,
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
                  color: AppColors.primary,
                  width: 1.1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.primary,
                  size: 16,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'اطلب بسهولة، ونحن نجهّز ونوصل مشترياتك',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
          if (_selectedCategoryId != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _selectCategory(null),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('عرض كل المنتجات'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'كل الأقسام',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'اختَر القسم الذي تبحث عنه',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عروض اليوم',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'وفر أكثر على مشترياتك',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
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
                                  color: AppColors.primary,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: _openOrders,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                _ReorderIcon(),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اطلب مرة ثانية',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'أعد طلبك السابق بدون ما تبدأ من الصفر',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(13),
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
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selected != null) ...[
                      Text(
                        _categoryEmoji(selected.name),
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  query.isNotEmpty ? '“$query” • $countText' : countText,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: _products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 0.66 : 0.72,
          ),
          itemBuilder: (context, index) =>
              ProductCard(product: _products[index]),
        );
      },
    );
  }

  String _categoryEmoji(String name) {
    final value = name.toLowerCase().trim();
    if (value.contains('مكسر') || value.contains('nuts')) return '🥜';
    if (value.contains('قهو') || value.contains('coffee')) return '☕';
    if (_isDairy(value)) return '🥛';
    if (value.contains('بقول') || value.contains('عدس')) return '🫘';
    if (value.contains('مخلل')) return '🫙';
    if (_isGrain(value)) return '🌾';
    if (value.contains('خض')) return '🥬';
    if (value.contains('فاكه') || value.contains('fruit')) return '🍎';
    if (value.contains('لحم') || value.contains('لحوم')) return '🥩';
    if (value.contains('دجاج')) return '🍗';
    if (value.contains('سمك') || value.contains('أسماك')) return '🐟';
    if (value.contains('خبز') || value.contains('مخبوز')) return '🥖';
    if (value.contains('بيض')) return '🥚';
    if (value.contains('حلوي') ||
        value.contains('حلوى') ||
        value.contains('شوكولا')) {
      return '🍫';
    }
    if (value.contains('بسكويت') || value.contains('كوكي')) return '🍪';
    if (value.contains('شيبس') || value.contains('سناك')) return '🍿';
    if (value.contains('مشروب') || value.contains('عصير')) return '🥤';
    if (value.contains('مياه') || value.contains('ماء')) return '💧';
    if (value.contains('معلب')) return '🥫';
    if (value.contains('بهار') || value.contains('توابل')) return '🌶️';
    if (value.contains('زيت') || value.contains('سمن')) return '🫒';
    if (value.contains('معكرون') || value.contains('باستا')) return '🍝';
    if (value.contains('شاي')) return '🫖';
    if (value.contains('سكر')) return '🍬';
    if (value.contains('منظف') || value.contains('تنظيف')) return '🧼';
    if (value.contains('ورقي') || value.contains('مناديل')) return '🧻';
    if (value.contains('عناية') || value.contains('شامبو')) return '🧴';
    if (value.contains('طفل') || value.contains('أطفال')) return '🍼';
    if (value.contains('مجمد')) return '❄️';
    if (value.contains('مثلج') || value.contains('آيس')) return '🍦';
    return '📦';
  }

  bool _isDairy(String value) {
    return value.contains('ألبان') ||
        value.contains('البان') ||
        value.contains('حليب') ||
        value.contains('لبن') ||
        value.contains('جبن') ||
        value.contains('زبادي') ||
        value.contains('dairy');
  }

  bool _isGrain(String value) {
    return value.contains('طحين') ||
        value.contains('دقيق') ||
        value.contains('أرز') ||
        value.contains('ارز') ||
        value.contains('رز') ||
        value.contains('حبوب') ||
        value.contains('برغل');
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
      color: selected
          ? AppColors.primary.withValues(alpha: 0.065)
          : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.42)
                  : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 27, height: 1)),
              const SizedBox(height: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderIcon extends StatelessWidget {
  const _ReorderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(
        Icons.replay_rounded,
        color: AppColors.primary,
        size: 21,
      ),
    );
  }
}
