import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/customer_address.dart';

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

    if (categoryId != null) query = query.eq('category_id', categoryId);

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
    if (user == null) throw StateError('تعذر تسجيل الدخول');

    await _client.from('customers').upsert({
      'id': user.id,
      'name': name,
      'phone': phone,
    });
  }

  static bool get isSignedIn => _client.auth.currentUser != null;

  static String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('يجب تسجيل الدخول قبل إتمام الطلب');
    }
    return userId;
  }

  static List<Map<String, dynamic>> _normalizeItems(
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) {
      throw ArgumentError('لا يمكن إنشاء طلب بدون منتجات');
    }

    final quantities = <String, int>{};
    for (final item in items) {
      final productId = item['product_id']?.toString();
      final rawQuantity = item['quantity'];
      final quantity = rawQuantity is num
          ? rawQuantity.toInt()
          : int.tryParse(rawQuantity?.toString() ?? '');

      if (productId == null ||
          productId.isEmpty ||
          quantity == null ||
          quantity <= 0) {
        throw ArgumentError('بيانات أحد المنتجات غير صالحة');
      }

      quantities[productId] = (quantities[productId] ?? 0) + quantity;
    }

    return quantities.entries
        .map((entry) => {'product_id': entry.key, 'quantity': entry.value})
        .toList(growable: false);
  }

  static Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
  }) async {
    const allowedPaymentMethods = {'cash', 'cliq', 'card'};
    if (!allowedPaymentMethods.contains(paymentMethod)) {
      throw ArgumentError('طريقة الدفع غير مدعومة');
    }

    _requireUserId();
    final normalizedItems = _normalizeItems(items);

    try {
      final result = await _client.rpc(
        'create_order',
        params: {
          'p_store_id': AppConfig.storeId,
          'p_items': normalizedItems,
          'p_payment_method': paymentMethod,
        },
      );

      if (result is! String || result.isEmpty) {
        throw StateError('تعذر إنشاء الطلب');
      }
      return result;
    } on PostgrestException catch (error) {
      _throwFriendlyCheckoutError(error);
    }
  }

  // ---------------------------------------------------------------------------
  // Delivery / address / checkout v2
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> getStoreOpenState() async {
    final result = await _client.rpc(
      'get_store_open_state',
      params: {'p_store_id': AppConfig.storeId},
    );
    return _mapFromRpc(result);
  }

  static Future<List<CustomerAddress>> fetchAddresses() async {
    final userId = _requireUserId();

    final data = await _client
        .from('addresses')
        .select()
        .eq('customer_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return (data as List)
        .map(
          (row) =>
              CustomerAddress.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  static Future<CustomerAddress> createAddress({
    required String label,
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
    String? notes,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String locationSource = 'manual',
    bool isDefault = false,
  }) async {
    final userId = _requireUserId();
    final payload = <String, dynamic>{
      'customer_id': userId,
      'label': _nullIfBlank(label),
      'city': _nullIfBlank(city),
      'area': _nullIfBlank(area),
      'street': _nullIfBlank(street),
      'building': _nullIfBlank(building),
      'floor': _nullIfBlank(floor),
      'notes': _nullIfBlank(notes),
      'lat': latitude,
      'lng': longitude,
      'location_accuracy_m': accuracyMeters,
      'location_source': _nullIfBlank(locationSource),
      'is_default': isDefault,
      'address_text': _buildAddressText(
        city: city,
        area: area,
        street: street,
        building: building,
        floor: floor,
      ),
    };

    final row = await _client
        .from('addresses')
        .insert(payload)
        .select()
        .single();

    return CustomerAddress.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<CustomerAddress> updateAddress({
    required String addressId,
    required String label,
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
    String? notes,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String locationSource = 'manual',
  }) async {
    final userId = _requireUserId();
    final payload = <String, dynamic>{
      'label': _nullIfBlank(label),
      'city': _nullIfBlank(city),
      'area': _nullIfBlank(area),
      'street': _nullIfBlank(street),
      'building': _nullIfBlank(building),
      'floor': _nullIfBlank(floor),
      'notes': _nullIfBlank(notes),
      'lat': latitude,
      'lng': longitude,
      'location_accuracy_m': accuracyMeters,
      'location_source': _nullIfBlank(locationSource),
      'address_text': _buildAddressText(
        city: city,
        area: area,
        street: street,
        building: building,
        floor: floor,
      ),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final row = await _client
        .from('addresses')
        .update(payload)
        .eq('id', addressId)
        .eq('customer_id', userId)
        .select()
        .single();

    return CustomerAddress.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<void> deleteAddress(String addressId) async {
    final userId = _requireUserId();
    await _client
        .from('addresses')
        .delete()
        .eq('id', addressId)
        .eq('customer_id', userId);
  }

  static Future<Map<String, dynamic>> getDeliveryServiceability({
    String? addressId,
    double? latitude,
    double? longitude,
    String? city,
    String? area,
  }) async {
    final result = await _client.rpc(
      'get_delivery_serviceability',
      params: {
        'p_store_id': AppConfig.storeId,
        'p_address_id': addressId,
        'p_lat': latitude,
        'p_lng': longitude,
        'p_city': _nullIfBlank(city),
        'p_area': _nullIfBlank(area),
      },
    );
    return _mapFromRpc(result);
  }

  static Future<Map<String, dynamic>> checkoutQuoteV2({
    required List<Map<String, dynamic>> items,
    required String addressId,
  }) async {
    _requireUserId();
    final normalizedItems = _normalizeItems(items);

    try {
      final result = await _client.rpc(
        'checkout_quote_v2',
        params: {
          'p_store_id': AppConfig.storeId,
          'p_items': normalizedItems,
          'p_address_id': addressId,
        },
      );
      return _mapFromRpc(result);
    } on PostgrestException catch (error) {
      _throwFriendlyCheckoutError(error);
    }
  }

  static Future<String> createDeliveryOrder({
    required List<Map<String, dynamic>> items,
    required String addressId,
    required String paymentMethod,
    String? customerNote,
    String substitutePolicy = 'call_me',
  }) async {
    const allowedPaymentMethods = {'cash', 'cliq', 'card'};
    if (!allowedPaymentMethods.contains(paymentMethod)) {
      throw ArgumentError('طريقة الدفع غير مدعومة');
    }

    _requireUserId();
    final normalizedItems = _normalizeItems(items);

    try {
      final result = await _client.rpc(
        'create_order_checkout_v2',
        params: {
          'p_store_id': AppConfig.storeId,
          'p_items': normalizedItems,
          'p_address_id': addressId,
          'p_payment_method': paymentMethod,
          'p_customer_note': _nullIfBlank(customerNote),
          'p_substitute_policy': substitutePolicy,
        },
      );

      final orderId = result?.toString() ?? '';
      if (orderId.isEmpty) {
        throw StateError('تعذر إنشاء الطلب');
      }
      return orderId;
    } on PostgrestException catch (error) {
      _throwFriendlyCheckoutError(error);
    }
  }

  static Never _throwFriendlyCheckoutError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toUpperCase();

    if (message.contains('INSUFFICIENT_STOCK')) {
      throw StateError('الكمية المطلوبة لم تعد متوفرة');
    }
    if (message.contains('PRODUCT_UNAVAILABLE') ||
        message.contains('UNAVAILABLE')) {
      throw StateError('أحد المنتجات لم يعد متوفرًا');
    }
    if (message.contains('INVALID_ADDRESS')) {
      throw StateError('عنوان التوصيل غير صالح أو لا يخص هذا الحساب');
    }
    if (message.contains('ADDRESS_REQUIRED')) {
      throw StateError('اختر عنوان التوصيل أولًا');
    }
    if (message.contains('OUTSIDE_DELIVERY_ZONES')) {
      throw StateError('العنوان خارج مناطق التوصيل الحالية');
    }
    if (message.contains('STORE_UNAVAILABLE') ||
        message.contains('ORDERS_PAUSED')) {
      throw StateError('المتجر لا يستقبل طلبات الآن');
    }
    if (message.contains('CUSTOMER PROFILE')) {
      throw StateError('بيانات الحساب غير مكتملة');
    }
    if (message.contains('PAYMENT METHOD')) {
      throw StateError('طريقة الدفع غير مدعومة');
    }
    if (message.contains('AUTH_REQUIRED') ||
        message.contains('PERMISSION') ||
        error.code == '42501') {
      throw StateError('يجب تسجيل الدخول لإتمام الطلب');
    }
    throw error;
  }

  static Map<String, dynamic> _mapFromRpc(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw StateError('استجابة غير متوقعة من الخادم');
  }

  static String? _nullIfBlank(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _buildAddressText({
    required String city,
    required String area,
    String? street,
    String? building,
    String? floor,
  }) {
    final parts = <String>[
      city.trim(),
      area.trim(),
      if ((street ?? '').trim().isNotEmpty) street!.trim(),
      if ((building ?? '').trim().isNotEmpty) 'بناية ${building!.trim()}',
      if ((floor ?? '').trim().isNotEmpty) 'طابق ${floor!.trim()}',
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.join('، ');
  }

  static Future<Map<String, dynamic>?> lookupProductByBarcode(
    String barcode,
  ) async {
    final normalized = barcode.trim();
    if (normalized.isEmpty) return null;

    final result = await _client.rpc(
      'lookup_product_by_barcode',
      params: {'p_store_id': AppConfig.storeId, 'p_barcode': normalized},
    );

    if (result == null) return null;
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    throw StateError('استجابة الباركود غير صالحة');
  }

  // ---------------------------------------------------------------------------
  // Existing PayTabs / store / tracking functionality preserved
  // ---------------------------------------------------------------------------

  static Future<String> startCardPayment(String orderId) async {
    try {
      final response = await _client.functions.invoke(
        'create-card-payment',
        body: {'order_id': orderId},
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError('تعذر بدء الدفع بالبطاقة');
      }
      final data = response.data;
      if (data is! Map || data['redirect_url'] is! String) {
        throw StateError('بوابة الدفع لم ترجع رابطًا صالحًا');
      }
      return data['redirect_url'] as String;
    } on FunctionException catch (error) {
      final details = error.details?.toString() ?? '';
      if (details.contains('not configured')) {
        throw StateError('الدفع بالبطاقة يحتاج تفعيل بيانات PayTabs أولًا');
      }
      throw StateError('تعذر بدء الدفع بالبطاقة');
    }
  }

  static Future<Map<String, dynamic>> reconcileCardPayment(
    String orderId,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'reconcile-card-payment',
        body: {'order_id': orderId},
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError('تعذر التحقق من حالة الدفع');
      }

      final data = response.data;
      if (data is! Map) {
        throw StateError('بوابة الدفع لم ترجع حالة صالحة');
      }
      return Map<String, dynamic>.from(data);
    } on FunctionException catch (error) {
      final details = error.details?.toString().toLowerCase() ?? '';
      if (details.contains('not configured')) {
        throw StateError('الدفع بالبطاقة يحتاج تفعيل بيانات PayTabs أولًا');
      }
      if (details.contains('forbidden') || details.contains('unauthorized')) {
        throw StateError('لا تملك صلاحية التحقق من هذا الطلب');
      }
      throw StateError('تعذر التحقق من حالة الدفع الآن');
    }
  }

  static Future<Map<String, dynamic>> getStorePaymentConfig() async {
    final data = await _client
        .from('stores')
        .select('cliq_alias, cliq_recipient_name')
        .eq('id', AppConfig.storeId)
        .maybeSingle();
    return data ?? <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getStoreContactConfig() async {
    final data = await _client
        .from('stores')
        .select('name, phone')
        .eq('id', AppConfig.storeId)
        .maybeSingle();
    return data ?? <String, dynamic>{};
  }

  static Stream<Map<String, dynamic>> watchOrder(String orderId) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(<String, dynamic>{});

    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .eq('customer_id', userId)
        .map((rows) => rows.isEmpty ? <String, dynamic>{} : rows.first);
  }

  static Stream<List<Map<String, dynamic>>> watchDriverLocation(
    String orderId,
  ) {
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

    final userId = _requireUserId();

    await _client.from('call_requests').insert({
      'store_id': AppConfig.storeId,
      'order_id': orderId,
      'customer_id': userId,
      'type': type,
      'status': 'requested',
    });
  }
}
