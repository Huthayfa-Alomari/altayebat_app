import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/category.dart';

// معرّف مول أسواق الطيبات — كل استعلام بالتطبيق مربوط فيه
// (لما نبيع النظام لمول جديد، بس بتغيّر هاد الرقم بنسخة التطبيق الخاصة فيه)
const String storeId = '61e6f35d-7004-4a33-948c-b297ba446678';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://wfvuojrhxewogdnynytf.supabase.co',
      anonKey: 'sb_publishable_GZV5SCGFY-32O3fz3ciUkg_2B6hYckJ',
    );
  }

  static Future<List<ProductCategory>> fetchCategories() async {
    final data = await _client
        .from('categories')
        .select()
        .eq('store_id', storeId)
        .order('sort_order');
    return (data as List)
        .map((e) => ProductCategory.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Product>> fetchProducts({String? categoryId}) async {
    var query = _client
        .from('products')
        .select()
        .eq('store_id', storeId)
        .eq('is_available', true);

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((e) => Product.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // تسجيل دخول مجهول (بدون تحقق SMS) وحفظ اسم ورقم الزبون
  // لاحقاً لما يكبر المشروع، منقدر نستبدلها بتحقق SMS حقيقي بدون
  // ما نغيّر بنية قاعدة البيانات — بس بنبدّل طريقة تسجيل الدخول هون.
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

    final order = await _client
        .from('orders')
        .insert({
          'store_id': storeId,
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

  // بث حي لحالة الطلب — يتحدث فور ما صاحب المول يغيّرها من لوحة التحكم
  static Stream<Map<String, dynamic>> watchOrder(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.first);
  }

  // بث حي لموقع المندوب أثناء التوصيل
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
    required String type, // voice | video | chat
    String? orderId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('call_requests').insert({
      'store_id': storeId,
      'order_id': orderId,
      'customer_id': userId,
      'type': type,
      'status': 'requested',
    });
  }
}