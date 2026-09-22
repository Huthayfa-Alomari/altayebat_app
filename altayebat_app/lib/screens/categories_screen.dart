import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<ProductCategory> _categories = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final categories = await CatalogService.fetchCategories(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التصنيفات. حاول مرة ثانية.';
      });
    }
  }

  List<ProductCategory> get _roots =>
      CatalogService.rootCategories(_categories);

  List<ProductCategory> _children(String parentId) =>
      CatalogService.childrenOf(_categories, parentId);

  Future<void> _openCategory(ProductCategory category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryProductsScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'التصنيفات',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: _error != null
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 100),
                        Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.textSecondary,
                          size: 46,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
                      itemCount: _roots.length,
                      itemBuilder: (context, index) {
                        final root = _roots[index];
                        final children = _children(root.id);
                        return _CategorySection(
                          root: root,
                          children: children,
                          onOpen: _openCategory,
                        );
                      },
                    ),
            ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final ProductCategory root;
  final List<ProductCategory> children;
  final Future<void> Function(ProductCategory category) onOpen;

  const _CategorySection({
    required this.root,
    required this.children,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cards = children.isEmpty ? <ProductCategory>[root] : children;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 14, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    root.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => onOpen(root),
                  child: const Text(
                    'عرض الكل',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(end: 14),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = cards[index];
                return _CategoryTile(
                  category: category,
                  onTap: () => onOpen(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ProductCategory category;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: Material(
        color: const Color(0xFFF6F7F8),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: _CategoryImage(
                      category: category,
                      size: 110,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  final ProductCategory category;
  final double size;

  const _CategoryImage({
    required this.category,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final url = category.imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        _categoryIcon(category.name),
        color: AppColors.navy,
        size: size * 0.42,
      ),
    );
  }
}

class CategoryProductsScreen extends StatefulWidget {
  final ProductCategory category;

  const CategoryProductsScreen({
    super.key,
    required this.category,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  static const _pageSize = CatalogService.defaultPageSize;
  final ScrollController _controller = ScrollController();

  List<Product> _products = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.hasClients &&
        _controller.position.extentAfter < 650 &&
        !_loading &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (forceRefresh) CatalogService.invalidateProducts();
      final page = await CatalogService.fetchProductsPage(
        categoryId: widget.category.id,
        offset: 0,
        limit: _pageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _products = page.items;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل المنتجات.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await CatalogService.fetchProductsPage(
        categoryId: widget.category.id,
        offset: _nextOffset,
        limit: _pageSize,
      );
      if (!mounted) return;
      final known = _products.map((item) => item.id).toSet();
      setState(() {
        _products = [
          ..._products,
          ...page.items.where((item) => known.add(item.id)),
        ];
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(
          widget.category.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: _error != null
                  ? ListView(
                      padding: const EdgeInsets.all(30),
                      children: [
                        const SizedBox(height: 100),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : CustomScrollView(
                      controller: _controller,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: 264,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  ProductCard(product: _products[index]),
                              childCount: _products.length,
                            ),
                          ),
                        ),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(22),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        if (_products.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                'لا توجد منتجات في هذا التصنيف حاليًا.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }
}

IconData _categoryIcon(String name) {
  final value = name.toLowerCase();
  if (value.contains('لحم') || value.contains('دجاج')) {
    return Icons.restaurant_rounded;
  }
  if (value.contains('ألبان') || value.contains('البان')) {
    return Icons.local_drink_rounded;
  }
  if (value.contains('مشروب') || value.contains('قهوة')) {
    return Icons.local_cafe_rounded;
  }
  if (value.contains('منزل') ||
      value.contains('تنظيف') ||
      value.contains('غسيل')) {
    return Icons.cleaning_services_rounded;
  }
  if (value.contains('عناية') || value.contains('طفل')) {
    return Icons.spa_rounded;
  }
  if (value.contains('مجمد')) return Icons.ac_unit_rounded;
  if (value.contains('سناكات') ||
      value.contains('حلويات') ||
      value.contains('مكسر')) {
    return Icons.cookie_rounded;
  }
  if (value.contains('بقالة') ||
      value.contains('أرز') ||
      value.contains('معكرونة')) {
    return Icons.shopping_basket_rounded;
  }
  return Icons.category_rounded;
}
