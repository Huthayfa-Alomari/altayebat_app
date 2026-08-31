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
        _errorMessage = 'تعذر تحميل المنتجات. تأكد من اتصال الإنترنت وحاول مرة ثانية.';
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

  Future<void> _search() => _loadProducts(categoryId: _selectedCategoryId);

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _search();
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
                          _categoryChips(),
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
            decoration: InputDecoration(
              hintText: 'دور عالمنتج يلي بدك ياه',
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
            onChanged: (_) => setState(() {}),
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

  Widget _categoryChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(
            'الكل',
            _selectedCategoryId == null,
            () => _loadProducts(categoryId: null),
          ),
          ..._categories.map(
            (c) => _chip(
              c.name,
              _selectedCategoryId == c.id,
              () => _loadProducts(categoryId: c.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _productGrid() {
    if (_products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _searchController.text.trim().isNotEmpty
                ? 'ما لقينا منتج مطابق لبحثك'
                : 'ما في منتجات بهاد التصنيف لسه',
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) => ProductCard(product: _products[index]),
    );
  }
}
