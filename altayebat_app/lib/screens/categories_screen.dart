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

  List<ProductCategory> get _rootCategories {
    final roots = _categories.where((item) => item.isRoot).toList();
    roots.sort(
      (a, b) => a.sortOrder.compareTo(b.sortOrder) != 0
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.name.compareTo(b.name),
    );
    return roots;
  }

  List<ProductCategory> _childrenOf(String parentId) {
    final children = _categories
        .where((item) => item.parentId == parentId)
        .toList();
    children.sort(
      (a, b) => a.sortOrder.compareTo(b.sortOrder) != 0
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.name.compareTo(b.name),
    );
    return children;
  }

  Future<void> _openCategory(ProductCategory category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CategoryProductsScreen(category: category),
      ),
    );
  }

  String? _resolvedImage(ProductCategory category) {
    final own = category.imageUrl?.trim();
    if (own != null && own.isNotEmpty) return own;

    for (final child in _childrenOf(category.id)) {
      final image = child.imageUrl?.trim();
      if (image != null && image.isNotEmpty) return image;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final roots = _rootCategories;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'التصنيفات',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'كل قسم وتحته التصنيفات الفرعية — وصول أسرع للمنتج',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: AppColors.textSecondary,
                            size: 42,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _load(),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (roots.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('لا توجد تصنيفات متاحة حاليًا.')),
                )
              else
                SliverList.builder(
                  itemCount: roots.length,
                  itemBuilder: (context, index) {
                    final root = roots[index];
                    final children = _childrenOf(root.id);
                    return _CategorySection(
                      category: root,
                      imageUrl: _resolvedImage(root),
                      children: children,
                      onOpen: _openCategory,
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final ProductCategory category;
  final String? imageUrl;
  final List<ProductCategory> children;
  final ValueChanged<ProductCategory> onOpen;

  const _CategorySection({
    required this.category,
    required this.imageUrl,
    required this.children,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => onOpen(category),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                children: [
                  _CategoryImage(
                    name: category.name,
                    imageUrl: imageUrl,
                    size: 74,
                    radius: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          children.isEmpty
                              ? 'تصفح المنتجات'
                              : '${children.length} تصنيفات فرعية',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => onOpen(category),
                    child: const Text(
                      'عرض الكل',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 154,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: children.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final child = children[index];
                  return SizedBox(
                    width: 124,
                    child: Material(
                      color: index.isEven
                          ? const Color(0xFFFFF5F6)
                          : const Color(0xFFF2F8FF),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () => onOpen(child),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Column(
                            children: [
                              Expanded(
                                child: _CategoryImage(
                                  name: child.name,
                                  imageUrl: child.imageUrl,
                                  size: 92,
                                  radius: 16,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                child.name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 11,
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
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryImage extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final double radius;

  const _CategoryImage({
    required this.name,
    required this.imageUrl,
    required this.size,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE8EEF5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 5),
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    final value = name.toLowerCase();
    final icon = value.contains('مشروب') || value.contains('قهوة')
        ? Icons.local_cafe_rounded
        : value.contains('تنظيف') || value.contains('منزل')
        ? Icons.cleaning_services_rounded
        : value.contains('طفل')
        ? Icons.child_friendly_rounded
        : value.contains('لحم') || value.contains('دواجن')
        ? Icons.restaurant_rounded
        : value.contains('ألبان') || value.contains('حليب')
        ? Icons.local_drink_rounded
        : value.contains('حلويات') || value.contains('سناكات')
        ? Icons.cookie_rounded
        : Icons.shopping_bag_rounded;

    return Center(
      child: Icon(icon, color: AppColors.navy, size: size * 0.42),
    );
  }
}

class _CategoryProductsScreen extends StatefulWidget {
  final ProductCategory category;

  const _CategoryProductsScreen({required this.category});

  @override
  State<_CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<_CategoryProductsScreen> {
  static const int _pageSize = CatalogService.defaultPageSize;

  final ScrollController _scrollController = ScrollController();
  List<Product> _products = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 600) {
      _loadMore();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (forceRefresh) CatalogService.invalidateProducts();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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
        _error = 'تعذر تحميل منتجات هذا القسم.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
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
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        title: Text(
          widget.category.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: _error != null && _products.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 180),
                        Center(child: Text(_error!)),
                      ],
                    )
                  : _products.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('لا توجد منتجات في هذا القسم حاليًا.')),
                      ],
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(14),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            MediaQuery.sizeOf(context).width >= 600 ? 3 : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 264 + ((textScale - 1) * 76),
                      ),
                      itemCount: _products.length + (_loadingMore ? 2 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _products.length) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        return ProductCard(product: _products[index]);
                      },
                    ),
            ),
    );
  }
}
