import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/product.dart';
import '../models/category.dart';

class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> initialize() async {
    AppConfig.validate();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  }

  static Future<List<ProductCategory>> fetchCategories() async {
    final data = await _client
        .from('categories')
        .select()
        .eq('store_id', AppConfig.storeId)
        .order('sort_order');

    return (data as List)
        .map((e) => ProductCategory.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Product>> fetchProducts({
    String? categoryId,
    String? searchQuery,
  }) async {
    var query = _client
        .from('products')
        .select()
        .eq('store_id', AppConfig.storeId)
        .eq('is_available', true);

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    final normalizedSearch = searchQuery?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      query = query.ilike('name', '%$normalizedSearch%');
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((e) => Product.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> signInAndSaveProfile({
    required String name,
    required String phone,
  }) async {
    var user = _client.auth.currentUser;
    if (user == null) {
      final res = await _client.auth.signInAnonymously();
      user = res.user;
    }
    if (user == null) throw Exception('تعذر تسجيل الدخول');

    await _client.from('customers').upsert({
      'id': user.id,
      'name': name,
      'phone': phone,
    });
  }

  static bool get isSignedIn => _client.auth.currentUser != null;

  static Future<String> createOrder({
    required List<Map<String, dynamic>> items,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('يجب تسجيل الدخول قبل إنشاء الطلب');
    }
    if (items.isEmpty) {
      throw ArgumentError('لا يمكن إنشاء طلب بدون منتجات');
    }

    final normalizedItems = <Map<String, dynamic>>[];
    final quantities = <String, int>{};

    for (final item in items) {
      final productId = item['product_id'] as String?;
      final quantity = item['quantity'] as int?;
      if (productId == null || productId.isEmpty || quantity == null || quantity <= 0) {
        throw ArgumentError('بيانات أحد المنتجات غير صالحة');
      }
      quantities[productId] = (quantities[productId] ?? 0) + quantity;
    }

    for (final entry in quantities.entries) {
      normalizedItems.add({
        'product_id': entry.key,
        'quantity': entry.value,
      });
    }

    try {
      final result = await _client.rpc(
        'create_order',
        params: {
          'p_store_id': AppConfig.storeId,
          'p_items': normalizedItems,
        },
      );

      if (result is! String || result.isEmpty) {
        throw StateError('تعذر إنشاء الطلب');
      }
      return result;
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('insufficient stock')) {
        throw StateError('الكمية المطلوبة لم تعد متوفرة');
      }
      if (message.contains('unavailable')) {
        throw StateError('أحد المنتجات لم يعد متوفرًا');
      }
      if (message.contains('customer profile')) {
        throw StateError('بيانات الحساب غير مكتملة');
      }
      rethrow;
    }
  }

  static Stream<Map<String, dynamic>> watchOrder(String orderId) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value(<String, dynamic>{});
    }

    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .eq('customer_id', userId)
        .map((rows) => rows.isEmpty ? <String, dynamic>{} : rows.first);
  }

  static Stream<List<Map<String, dynamic>>> watchDriverLocation(
      String orderId) {
    return _client
        .from('driver_locations')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('updated_at', ascending: false)
        .limit(1);
  }

  static Future<void> requestCall({
    required String type,
    String? orderId,
  }) async {
    const supportedTypes = {'voice', 'video', 'chat'};
    if (!supportedTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'نوع التواصل غير مدعوم');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('يجب تسجيل الدخول قبل طلب التواصل');
    }

    await _client.from('call_requests').insert({
      'store_id': AppConfig.storeId,
      'order_id': orderId,
      'customer_id': userId,
      'type': type,
      'status': 'requested',
    });
  }
}
