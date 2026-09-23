import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../models/category_tree.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cart_bar.dart';
import '../widgets/category_artwork.dart';
import '../widgets/product_card.dart';
import 'cart_screen.dart';

class CategoryProductsScreen extends StatefulWidget {
  final ProductCategory category;
  final List<ProductCategory> categories;
  final CatalogRepository repository;
  const CategoryProductsScreen({
    super.key,
    required this.category,
    this.categories = const [],
    this.repository = const CatalogRepository(),
  });
  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  late ProductCategory _selected;
  late List<ProductCategory> _categories;
  List<Product> _products = const [];
  CatalogSort _sort = CatalogSort.newest;
  bool _inStockOnly = false,
      _loading = true,
      _loadingMore = false,
      _hasMore = false;
  int _nextOffset = 0, _generation = 0;
  String? _error, _moreError;
  CategoryTree get _tree => CategoryTree(_categories);
  ProductCategory get _root => _tree.rootOf(_selected);
  @override
  void initState() {
    super.initState();
    _selected = widget.category;
    _categories = widget.categories;
    _scroll.addListener(_onScroll);
    _load(refreshCategories: _categories.isEmpty);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 500 &&
        _moreError == null) {
      _loadMore();
    }
  }

  Future<void> _load({
    bool forceRefresh = false,
    bool refreshCategories = false,
  }) async {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = false;
      _nextOffset = 0;
      _error = null;
      _moreError = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.repository.products(
          categoryId: _selected.id,
          searchQuery: _search.text.trim(),
          sort: _sort,
          inStockOnly: _inStockOnly,
          forceRefresh: forceRefresh,
        ),
        if (refreshCategories)
          widget.repository.categories(forceRefresh: forceRefresh),
      ]);
      if (!mounted || generation != _generation) return;
      final page = results.first as CatalogPage;
      setState(() {
        if (refreshCategories) {
          _categories = results[1] as List<ProductCategory>;
        }
        _products = page.items;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = 'تعذر تحميل المنتجات. حاول مرة ثانية.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.repository.products(
        categoryId: _selected.id,
        searchQuery: _search.text.trim(),
        offset: _nextOffset,
        sort: _sort,
        inStockOnly: _inStockOnly,
      );
      if (!mounted || generation != _generation) return;
      final known = _products.map((p) => p.id).toSet();
      setState(() {
        _products = [..._products, ...page.items.where((p) => known.add(p.id))];
        _hasMore = page.hasMore && page.nextOffset > _nextOffset;
        _nextOffset = page.nextOffset;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loadingMore = false;
          _moreError = 'تعذر تحميل المزيد';
        });
      }
    }
  }

  void _select(ProductCategory category) {
    FocusScope.of(context).unfocus();
    if (_selected.id == category.id) return;
    setState(() => _selected = category);
    _load();
  }

  void _searchChanged(String value) {
    // Invalidate immediately so older responses cannot arrive during debounce.
    _debounce?.cancel();
    ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load();
    });
  }

  Future<void> _chooseSort() async {
    final sort = await showModalBottomSheet<CatalogSort>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'ترتيب المنتجات',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          for (final value in CatalogSort.values)
            ListTile(
              title: Text(value.label),
              selected: _sort == value,
              leading: Icon(
                _sort == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () => Navigator.pop(context, value),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (mounted && sort != null && sort != _sort) {
      setState(() => _sort = sort);
      _load();
    }
  }

  Future<void> _chooseCategory() async {
    final tree = _tree;
    final selected = await showModalBottomSheet<ProductCategory>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'تسوق الأقسام',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final root in tree.roots)
                    ExpansionTile(
                      initiallyExpanded: root.id == _root.id,
                      leading: CategoryArtwork(category: root, size: 44),
                      title: Text(root.name),
                      children: [
                        ListTile(
                          title: Text('عرض كل ${root.name}'),
                          onTap: () => Navigator.pop(context, root),
                        ),
                        for (final child in tree.descendantsOf(root.id))
                          ListTile(
                            leading: CategoryArtwork(category: child, size: 40),
                            title: Text(child.name),
                            selected: child.id == _selected.id,
                            onTap: () => Navigator.pop(context, child),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) _select(selected);
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    final options = [root, ..._tree.descendantsOf(root.id)];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            root.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          actions: [
            Selector<CartProvider, int>(
              selector: (_, cart) => cart.itemCount,
              builder: (context, count, child) => IconButton(
                tooltip: 'السلة',
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const CartScreen())),
                icon: Badge.count(
                  count: count,
                  isLabelVisible: count > 0,
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  onSubmitted: (_) {
                    FocusScope.of(context).unfocus();
                    _load();
                  },
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث داخل القسم…',
                    fillColor: AppColors.softSurface,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.navy,
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح البحث',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              _load();
                            },
                          ),
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final rail = constraints.maxWidth >= 360 && scale <= 1.3;
                    return Column(
                      children: [
                        if (!rail)
                          SizedBox(
                            height: 64 + (scale - 1).clamp(0, 3) * 18,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              itemCount: options.length,
                              separatorBuilder: (_, i) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) => ChoiceChip(
                                label: Text(i == 0 ? 'الكل' : options[i].name),
                                selected: options[i].id == _selected.id,
                                selectedColor: AppColors.skySoft,
                                onSelected: (_) => _select(options[i]),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (rail)
                                SizedBox(
                                  width: constraints.maxWidth >= 600 ? 108 : 80,
                                  child: ColoredBox(
                                    color: AppColors.softSurface,
                                    child: ListView.builder(
                                      itemCount: options.length,
                                      itemBuilder: (_, i) => _RailItem(
                                        category: options[i],
                                        selected: options[i].id == _selected.id,
                                        isAll: i == 0,
                                        onTap: () => _select(options[i]),
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _chooseSort,
                                            icon: const Icon(
                                              Icons.swap_vert_rounded,
                                              size: 19,
                                            ),
                                            label: Text(
                                              _sort == CatalogSort.newest
                                                  ? 'ترتيب'
                                                  : _sort.label,
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              foregroundColor: AppColors.navy,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: _chooseCategory,
                                            icon: const Icon(
                                              Icons.grid_view_rounded,
                                              size: 18,
                                            ),
                                            label: const Text('الأقسام'),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              foregroundColor: AppColors.navy,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          FilterChip(
                                            label: const Text('المتوفر فقط'),
                                            selected: _inStockOnly,
                                            selectedColor: AppColors.skySoft,
                                            onSelected: (value) {
                                              setState(
                                                () => _inStockOnly = value,
                                              );
                                              _load();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        8,
                                      ),
                                      child: Text(
                                        _selected.id == root.id
                                            ? 'كل ${root.name}'
                                            : _selected.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: _productList()),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const CartBar(),
      ),
    );
  }

  Widget _productList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true, refreshCategories: true),
      child: CustomScrollView(
        key: ValueKey(
          'products-${_selected.id}-${_sort.name}-$_inStockOnly-${_search.text}',
        ),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (_error != null || _products.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _error != null
                          ? Icons.cloud_off_outlined
                          : Icons.search_off_rounded,
                      size: 40,
                      color: AppColors.skyBlueDark,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error ?? 'لا توجد منتجات مطابقة حاليًا',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        if (_error == null) {
                          _search.clear();
                          _inStockOnly = false;
                        }
                        _load(forceRefresh: true);
                      },
                      child: Text(
                        _error == null ? 'عرض منتجات القسم' : 'إعادة المحاولة',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final minWidth = scale > 1.6 ? 230.0 : 125.0;
                final columns = ((constraints.crossAxisExtent - 16) / minWidth)
                    .floor()
                    .clamp(1, 4);
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 8,
                      mainAxisExtent: 278 + (scale - 1).clamp(0, 3) * 110,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) =>
                          ProductCard(product: _products[i], compact: true),
                      childCount: _products.length,
                    ),
                  ),
                );
              },
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_hasMore && !_loadingMore && _error == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(
                  onPressed: _loadMore,
                  child: Text(
                    _moreError == null
                        ? 'عرض المزيد'
                        : 'إعادة محاولة تحميل المزيد',
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final ProductCategory category;
  final bool selected, isAll;
  final VoidCallback onTap;
  const _RailItem({
    required this.category,
    required this.selected,
    required this.isAll,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: isAll ? 'كل منتجات القسم' : category.name,
    child: Material(
      color: selected ? Colors.white : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          decoration: BoxDecoration(
            border: BorderDirectional(
              end: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isAll ? AppColors.navy : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.skyBlue : AppColors.border,
                  ),
                ),
                child: isAll
                    ? const Icon(
                        Icons.grid_view_rounded,
                        color: Colors.white,
                        size: 25,
                      )
                    : CategoryArtwork(category: category, size: 56),
              ),
              const SizedBox(height: 7),
              Text(
                isAll ? 'الكل' : category.name,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected ? AppColors.navy : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
