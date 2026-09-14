import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/category.dart';
import '../models/product.dart';

class CatalogPage {
  final List<Product> items;
  final bool hasMore;
  final int nextOffset;

  const CatalogPage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });
}

class _TimedValue<T> {
  final T value;
  final DateTime expiresAt;

  const _TimedValue(this.value, this.expiresAt);

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class CatalogService {
  CatalogService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static const int defaultPageSize = 30;
  static const Duration _categoryTtl = Duration(minutes: 10);
  static const Duration _productPageTtl = Duration(minutes: 2);

  static const String _productColumns =
      'id,name,price,image_url,stock_qty,is_available,category_id,'
      'sale_type,base_unit,inventory_scale,price_per_unit,min_qty,qty_step,'
      'allow_amount_purchase';

  static _TimedValue<List<ProductCategory>>? _categoryCache;
  static Future<List<ProductCategory>>? _categoryInFlight;

  static final Map<String, _TimedValue<CatalogPage>> _pageCache = {};
  static final Map<String, Future<CatalogPage>> _pageInFlight = {};

  static String _pageKey({
    required String? categoryId,
    required String? searchQuery,
    required int offset,
    required int limit,
  }) {
    final search = searchQuery?.trim().toLowerCase() ?? '';
    return '${categoryId ?? '*'}|$search|$offset|$limit';
  }

  static Future<List<ProductCategory>> fetchCategories({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _categoryCache;
      if (cached != null && cached.isFresh) return cached.value;
      final pending = _categoryInFlight;
      if (pending != null) return pending;
    }

    final future = _loadCategories();
    _categoryInFlight = future;
    try {
      final value = await future;
      _categoryCache = _TimedValue(value, DateTime.now().add(_categoryTtl));
      return value;
    } finally {
      if (identical(_categoryInFlight, future)) _categoryInFlight = null;
    }
  }

  static Future<List<ProductCategory>> _loadCategories() async {
    final data = await _client
        .from('categories')
        .select('id,name,sort_order')
        .eq('store_id', AppConfig.storeId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');

    return (data as List)
        .map(
          (row) =>
              ProductCategory.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  static Future<CatalogPage> fetchProductsPage({
    String? categoryId,
    String? searchQuery,
    int offset = 0,
    int limit = defaultPageSize,
    bool forceRefresh = false,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(10, 60).toInt();
    final key = _pageKey(
      categoryId: categoryId,
      searchQuery: searchQuery,
      offset: safeOffset,
      limit: safeLimit,
    );

    if (!forceRefresh) {
      final cached = _pageCache[key];
      if (cached != null && cached.isFresh) return cached.value;
      final pending = _pageInFlight[key];
      if (pending != null) return pending;
    }

    final future = _loadProductsPage(
      categoryId: categoryId,
      searchQuery: searchQuery,
      offset: safeOffset,
      limit: safeLimit,
    );
    _pageInFlight[key] = future;

    try {
      final value = await future;
      _pageCache[key] = _TimedValue(value, DateTime.now().add(_productPageTtl));
      return value;
    } finally {
      if (identical(_pageInFlight[key], future)) _pageInFlight.remove(key);
    }
  }

  static Future<CatalogPage> _loadProductsPage({
    required String? categoryId,
    required String? searchQuery,
    required int offset,
    required int limit,
  }) async {
    var query = _client
        .from('products')
        .select(_productColumns)
        .eq('store_id', AppConfig.storeId)
        .eq('is_available', true);

    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.eq('category_id', categoryId);
    }

    final search = searchQuery?.trim();
    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final items = (data as List)
        .map((row) => Product.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);

    return CatalogPage(
      items: items,
      hasMore: items.length == limit,
      nextOffset: offset + items.length,
    );
  }

  static void invalidateProducts() {
    _pageCache.clear();
  }

  static void invalidateAll() {
    _categoryCache = null;
    _pageCache.clear();
  }
}
