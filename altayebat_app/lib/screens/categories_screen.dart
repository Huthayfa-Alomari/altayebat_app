import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/category_tree.dart';
import '../services/catalog_service.dart';
import '../settings/app_language.dart';
import '../theme/app_theme.dart';
import '../widgets/altayebat_brand.dart';
import '../widgets/category_artwork.dart';
import 'category_products_screen.dart';
export 'category_products_screen.dart';

class CategoriesScreen extends StatefulWidget {
  final CatalogRepository repository;
  const CategoriesScreen({
    super.key,
    this.repository = const CatalogRepository(),
  });
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _search = TextEditingController();
  List<ProductCategory> _categories = const [];
  bool _loading = true;
  String? _error;
  String? _rootId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await widget.repository.categories(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
        if (!categories.any((c) => c.id == _rootId)) _rootId = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر تحميل الأقسام. تأكد من الاتصال وحاول مرة ثانية.';
        });
      }
    }
  }

  void _open(ProductCategory category) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CategoryProductsScreen(
        category: category,
        categories: _categories,
        repository: widget.repository,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final english = AppLanguage.isEnglish(context);
    String t(String ar, String en) => AppLanguage.text(context, ar, en);
    final tree = CategoryTree(_categories);
    final query = normalizeCategoryName(_search.text);
    final roots = tree.roots
        .where(
          (root) =>
              (_rootId == null || root.id == _rootId) &&
              (query.isEmpty ||
                  normalizeCategoryName(
                    root.displayName(english),
                  ).contains(query) ||
                  tree
                      .descendantsOf(root.id)
                      .any(
                        (c) => normalizeCategoryName(
                          c.displayName(english),
                        ).contains(query),
                      )),
        )
        .toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              color: AppColors.navy,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (Navigator.of(context).canPop())
                        IconButton(
                          tooltip: t('رجوع', 'Back'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('كل الأقسام', 'All categories'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              t(
                                'كل احتياجات بيتك، مرتبة إلك',
                                'Everything your home needs, in one place',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const AltayebatAppMark(size: 46),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: t(
                        'ابحث عن قسم أو صنف…',
                        'Search categories or products…',
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.navy,
                      ),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: t('مسح البحث', 'Clear search'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_loading && _categories.isNotEmpty)
              SizedBox(
                height:
                    62 +
                    (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(
                          0,
                          3,
                        ) *
                        18,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  itemCount: tree.roots.length + 1,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final root = index == 0 ? null : tree.roots[index - 1];
                    return ChoiceChip(
                      label: Text(
                        root?.displayName(english) ?? t('الكل', 'All'),
                      ),
                      selected: _rootId == root?.id,
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      onSelected: (_) => setState(() => _rootId = root?.id),
                    );
                  },
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _load(forceRefresh: true),
                      child: _error != null || roots.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(32),
                              children: [
                                const SizedBox(height: 60),
                                Icon(
                                  _error != null
                                      ? Icons.cloud_off_outlined
                                      : Icons.search_off_rounded,
                                  size: 44,
                                  color: AppColors.skyBlueDark,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _error ??
                                      (query.isEmpty
                                          ? t(
                                              'الأقسام قيد التجهيز',
                                              'Categories are being prepared',
                                            )
                                          : t(
                                              'ما لقينا قسم بهذا الاسم',
                                              'No matching category',
                                            )),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                if (_error != null)
                                  FilledButton(
                                    onPressed: () => _load(forceRefresh: true),
                                    child: Text(
                                      t('إعادة المحاولة', 'Try again'),
                                    ),
                                  ),
                                if (_error == null && query.isNotEmpty)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _search.clear();
                                      _rootId = null;
                                    }),
                                    child: Text(
                                      t(
                                        'عرض جميع الأقسام',
                                        'Show all categories',
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : ListView.builder(
                              key: ValueKey('sections-$_rootId-$query'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: roots.length,
                              itemBuilder: (context, index) {
                                final root = roots[index];
                                final children = tree.childrenOf(root.id);
                                final matches = normalizeCategoryName(
                                  root.displayName(english),
                                ).contains(query);
                                final cards = query.isEmpty || matches
                                    ? (children.isEmpty ? [root] : children)
                                    : tree
                                          .descendantsOf(root.id)
                                          .where(
                                            (c) => normalizeCategoryName(
                                              c.displayName(english),
                                            ).contains(query),
                                          )
                                          .toList();
                                return CategorySection(
                                  root: root,
                                  categories: cards,
                                  onOpen: _open,
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategorySection extends StatelessWidget {
  final ProductCategory root;
  final List<ProductCategory> categories;
  final ValueChanged<ProductCategory> onOpen;
  const CategorySection({
    super.key,
    required this.root,
    required this.categories,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    root.displayName(AppLanguage.isEnglish(context)),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => onOpen(root),
                  child: Text(
                    AppLanguage.text(context, 'عرض الكل', 'View all'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 174 + (scale - 1).clamp(0, 3) * 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, index) => const SizedBox(width: 10),
              itemBuilder: (_, index) => SizedBox(
                width: 118,
                child: CategoryTile(
                  category: categories[index],
                  onTap: () => onOpen(categories[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
