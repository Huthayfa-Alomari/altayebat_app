import 'dart:async';
import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_bar.dart';
import '../widgets/call_fab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<ProductCategory> _categories = [];
  List<Product> _products = [];
  String? _selectedCategoryId;
  String? _errorMessage;
  bool _loading = true;
  bool _loadingProducts = false;

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
      final results = await Future.wait([
        SupabaseService.fetchCategories(),
        SupabaseService.fetchProducts(
          categoryId: _selectedCategoryId,
          searchQuery: _searchController.text,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<ProductCategory>;
        _products = results[1] as List<Product>;
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
    setState(() {
      _selectedCategoryId = categoryId;
      _loadingProducts = true;
      _errorMessage = null;
    });

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

    if (query.isNotEmpty && _selectedCategoryId != null && mounted) {
      setState(() => _selectedCategoryId = null);
    }

    await _loadProducts(categoryId: query.isEmpty ? _selectedCategoryId : null);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (mounted) {
      setState(() {
        if (query.isNotEmpty) _selectedCategoryId = null;
      });
    }

    if (query.isEmpty) {
      _loadProducts(categoryId: null);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _loadProducts(categoryId: null);
    });
  }

  Future<void> _clearSearch() async {
    if (_searchController.text.isEmpty) return;
    _searchDebounce?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (mounted) setState(() {});
    await _loadProducts(categoryId: null);
  }

  Future<void> _selectCategory(String? categoryId) async {
    _searchDebounce?.cancel();

    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }

    FocusScope.of(context).unfocus();
    if (mounted) setState(() {});
    await _loadProducts(categoryId: categoryId);
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
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8),
                        children: [
                          if (_errorMessage != null) _errorState(),
                          if (_searchController.text.trim().isEmpty)
                            _categoryChips(),
                          _resultsHeader(),
                          if (_loadingProducts)
                            const Padding(
                              padding: EdgeInsets.all(28),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
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
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أسواق الطيبات',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'تسوّق بسهولة ووصل طلبك لباب البيت',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.notifications_none, color: Colors.white),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'شو بدك؟ ابحث باسم المنتج',
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: AppColors.textSecondary,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close, size: 18),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onSearchChanged,
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
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

  List<ProductCategory> _orderedCategories() {
    const order = <String>[
      'الأرز',
      'الزيوت',
      'معكرونة وشعيرية',
      'الألبان والأجبان',
      'المجمدات',
      'المشروبات',
      'مرقة وشوربات',
      'سكر ومستلزمات الخَبز',
      'معلبات وصلصات',
      'طحينية وحلاوة ومربى',
      'اللحوم والدواجن',
      'غسيل الملابس',
      'تنظيف المنزل والجلي',
      'مناديل وورقيات',
      'العناية الشخصية',
    ];

    final priority = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };

    final result = List<ProductCategory>.from(_categories);
    result.sort((a, b) {
      final aRank = priority[a.name] ?? 999;
      final bRank = priority[b.name] ?? 999;
      if (aRank != bRank) return aRank.compareTo(bRank);
      return a.name.compareTo(b.name);
    });
    return result;
  }

  IconData _categoryIcon(String name) {
    if (name.contains('أرز') ||
        name.contains('معكرونة') ||
        name.contains('مرقة')) {
      return Icons.restaurant_outlined;
    }
    if (name.contains('زيوت')) return Icons.water_drop_outlined;
    if (name.contains('ألبان') || name.contains('أجبان')) {
      return Icons.kitchen_outlined;
    }
    if (name.contains('مجمدات')) return Icons.ac_unit;
    if (name.contains('مشروبات')) return Icons.local_cafe_outlined;
    if (name.contains('غسيل') || name.contains('تنظيف')) {
      return Icons.cleaning_services_outlined;
    }
    if (name.contains('مناديل')) return Icons.inventory_2_outlined;
    if (name.contains('العناية')) return Icons.spa_outlined;
    if (name.contains('معلبات') ||
        name.contains('طحينية') ||
        name.contains('سكر')) {
      return Icons.shopping_basket_outlined;
    }
    if (name.contains('لحوم')) return Icons.restaurant_menu_outlined;
    return Icons.category_outlined;
  }

  Widget _categoryCard(
    ProductCategory category, {
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final selected = _selectedCategoryId == category.id;

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.10)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _categoryIcon(category.name),
                  size: 21,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllCategories() async {
    final categories = _orderedCategories();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'كل الأقسام',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _selectCategory(null);
                      },
                      icon: const Icon(Icons.apps_outlined),
                      label: const Text('عرض كل المنتجات'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 650 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: categories.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: columns == 3 ? 2.6 : 2.15,
                        ),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          return _categoryCard(
                            category,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _loadProducts(categoryId: category.id);
                            },
                          );
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

  Widget _categoryChips() {
    final categories = _orderedCategories();
    final featured = categories.take(6).toList();
    final theme = Theme.of(context);

    if (featured.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الأقسام الرئيسية',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showAllCategories,
                child: const Text('كل الأقسام'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 650 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: featured.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 3 ? 2.7 : 2.15,
                ),
                itemBuilder: (context, index) {
                  final category = featured[index];
                  return _categoryCard(
                    category,
                    onTap: () => _selectCategory(category.id),
                  );
                },
              );
            },
          ),
          if (_selectedCategoryId != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _selectCategory(null),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('إلغاء التصنيف وعرض الكل'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultsHeader() {
    final query = _searchController.text.trim();

    ProductCategory? selected;
    if (_selectedCategoryId != null) {
      for (final category in _categories) {
        if (category.id == _selectedCategoryId) {
          selected = category;
          break;
        }
      }
    }

    final title = query.isNotEmpty
        ? 'نتائج البحث'
        : selected?.name ?? 'كل المنتجات';
    final countText = _loadingProducts
        ? 'جاري التحميل...'
        : '${_products.length} منتج';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  query.isNotEmpty ? '“$query” • $countText' : countText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (query.isNotEmpty)
            TextButton(onPressed: _clearSearch, child: const Text('مسح'))
          else if (_selectedCategoryId != null)
            TextButton(
              onPressed: () => _selectCategory(null),
              child: const Text('عرض الكل'),
            ),
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
            Icon(
              _searchController.text.trim().isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.inventory_2_outlined,
              size: 42,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _searchController.text.trim().isNotEmpty
                  ? 'ما لقينا المنتج'
                  : 'ما في منتجات بهاد القسم حاليًا',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (_searchController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'جرّب كلمة أقصر أو اسم الماركة',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _clearSearch,
                child: const Text('عرض كل المنتجات'),
              ),
            ],
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          itemCount: _products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 0.60 : 0.68,
          ),
          itemBuilder: (context, index) =>
              ProductCard(product: _products[index]),
        );
      },
    );
  }
}
