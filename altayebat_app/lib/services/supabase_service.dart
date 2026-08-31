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
      anonKey: AppConfig.supabaseAnonKey,
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
    required double total,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('يجب تسجيل الدخول قبل إنشاء الطلب');
    }
    if (items.isEmpty) {
      throw ArgumentError('لا يمكن إنشاء طلب بدون منتجات');
    }
    if (total <= 0) {
      throw ArgumentError('إجمالي الطلب غير صالح');
    }

    final order = await _client
        .from('orders')
        .insert({
          'store_id': AppConfig.storeId,
          'customer_id': userId,
          'total': total,
          'status': 'pending',
        })
        .select()
        .single();

    final orderId = order['id'] as String;

    final orderItems = items
        .map((item) => {
              'order_id': orderId,
              'product_id': item['product_id'],
              'quantity': item['quantity'],
              'unit_price': item['unit_price'],
            })
        .toList();

    await _client.from('order_items').insert(orderItems);

    return orderId;
  }

  static Stream<Map<String, dynamic>> watchOrder(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
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
