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
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 12),
                        children: [
                          if (_errorMessage != null) _errorState(),
                          if (_searchController.text.trim().isEmpty) ...[
                            _quickActions(),
                            if (_offers.isNotEmpty) _offersSection(),
                            _categoryGrid(),
                          ],
                          _resultsHeader(),
                          if (_loadingProducts)
                            const Padding(
                              padding: EdgeInsets.all(30),
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
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أسواق الطيبات',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 1),
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
                    color: const Color(0xFFF5F5F3),
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
          const SizedBox(height: 13),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'ابحث عن منتج...',
              hintStyle: const TextStyle(
                color: Color(0xFF929292),
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
              fillColor: const Color(0xFFF4F4F2),
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
                  width: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 17,
                  color: AppColors.primary,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'اطلب بسهولة، ونحن نجهز ونوصل مشترياتك',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 11.5,
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

  Widget _quickActions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: _surfaceDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.replay_rounded,
              title: 'إعادة الطلب',
              subtitle: 'كرر طلبك السابق',
              onTap: _openOrders,
            ),
          ),
          Container(width: 1, height: 42, color: AppColors.border),
          Expanded(
            child: _QuickAction(
              icon: Icons.local_offer_outlined,
              title: 'العروض',
              subtitle: _offers.isEmpty
                  ? 'تابع أحدث العروض'
                  : '${_offers.length} عرض متوفر',
              onTap: () {
                if (_offers.isEmpty) return;
                _openOffer(_offers.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _offersSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('عروض اليوم', 'وفر أكثر على مشترياتك'),
          const SizedBox(height: 9),
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _offers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final offer = _offers[index];
                return SizedBox(
                  width: 244,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _openOffer(offer),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFF3D6D7)),
                          gradient: const LinearGradient(
                            begin: AlignmentDirectional.topStart,
                            end: AlignmentDirectional.bottomEnd,
                            colors: [Color(0xFFFFFBFB), Color(0xFFFFF4F4)],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
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
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                const Text(
                                  '🏷️',
                                  style: TextStyle(fontSize: 18),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            Text(
                              offer.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
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
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  offer.regularPricePerUnit.toStringAsFixed(2),
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 11,
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

  Widget _categoryGrid() {
    if (_categories.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: _surfaceDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تسوّق حسب القسم',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'اختَر القسم لتوصل للمنتجات أسرع',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 6 : 4;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _categories.length + 1,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.93,
                ),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CategoryTile(
                      emoji: '🛒',
                      label: 'الكل',
                      selected: _selectedCategoryId == null,
                      onTap: () => _selectCategory(null),
                    );
                  }

                  final category = _categories[index - 1];
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

  String _categoryEmoji(String name) {
    final value = name.toLowerCase().trim();
    if (value.contains('مكسر') || value.contains('nuts')) return '🥜';
    if (value.contains('قهو') || value.contains('coffee')) return '☕';
    if (value.contains('ألبان') ||
        value.contains('البان') ||
        value.contains('حليب') ||
        value.contains('لبن') ||
        value.contains('dairy')) {
      return '🥛';
    }
    if (value.contains('بقول')) return '🫘';
    if (value.contains('مخلل')) return '🫙';
    if (value.contains('طحين') || value.contains('دقيق')) return '🌾';
    if (value.contains('أرز') ||
        value.contains('ارز') ||
        value.contains('رز') ||
        value.contains('حبوب') ||
        value.contains('برغل')) {
      return '🌾';
    }
    if (value.contains('خض')) return '🥬';
    if (value.contains('فاكه') || value.contains('fruit')) return '🍎';
    if (value.contains('لحم') || value.contains('لحوم')) return '🥩';
    if (value.contains('دجاج')) return '🍗';
    if (value.contains('سمك') || value.contains('أسماك')) return '🐟';
    if (value.contains('خبز') || value.contains('مخبوز')) return '🥖';
    if (value.contains('حلوي') || value.contains('حلوى')) return '🍫';
    if (value.contains('مشروب') || value.contains('عصير')) return '🥤';
    if (value.contains('مياه') || value.contains('ماء')) return '💧';
    if (value.contains('معلب')) return '🥫';
    if (value.contains('بهار') || value.contains('توابل')) return '🌶️';
    if (value.contains('منظف')) return '🧼';
    if (value.contains('عناية') || value.contains('شامبو')) return '🧴';
    if (value.contains('طفل') || value.contains('أطفال')) return '🍼';
    if (value.contains('مجمد')) return '❄️';
    return '🛍️';
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _surfaceDecoration({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFFECEBE7)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 14,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
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
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
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
                          fontSize: 17,
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
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 44, 24, 56),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 44,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'ما في منتجات متوفرة حاليًا',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
          itemCount: _products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            childAspectRatio: columns == 2 ? 0.61 : 0.68,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.075),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
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
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9.5,
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
          ? AppColors.primary.withValues(alpha: 0.075)
          : const Color(0xFFFAFAF8),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : const Color(0xFFECEBE7),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 39,
                height: 39,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 7,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 21)),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
