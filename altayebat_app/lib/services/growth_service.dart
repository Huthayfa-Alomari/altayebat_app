import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/product.dart';
import '../models/reorder_result.dart';
import '../models/store_offer.dart';

class GrowthService {
  GrowthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static String? get _userId => _client.auth.currentUser?.id;

  static Future<void> refreshExpiredOffers() async {
    try {
      await _client.rpc(
        'refresh_expired_offers',
        params: {'p_store_id': AppConfig.storeId},
      );
    } catch (_) {
      // Backward compatible while the growth migration is not deployed yet.
    }
  }

  static Future<List<StoreOffer>> fetchActiveOffers() async {
    await refreshExpiredOffers();
    try {
      final data = await _client
          .from('store_offers')
          .select(
            'id,product_id,title,subtitle,regular_price_per_unit,'
            'offer_price_per_unit,ends_at,products(name,image_url)',
          )
          .eq('store_id', AppConfig.storeId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(20);

      return (data as List)
          .map(
            (row) => StoreOffer.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .where((offer) => offer.id.isNotEmpty && offer.productId.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <StoreOffer>[];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMyOrders({
    int limit = 30,
  }) async {
    final userId = _userId;
    if (userId == null) return const [];

    final data = await _client
        .from('orders')
        .select(
          'id,status,total,subtotal,delivery_fee,payment_method,'
          'payment_status,created_at,updated_at',
        )
        .eq('customer_id', userId)
        .eq('store_id', AppConfig.storeId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  static Future<ReorderResult> buildReorder(String orderId) async {
    if (_userId == null) {
      throw StateError('يجب تسجيل الدخول لعرض الطلبات السابقة');
    }

    final data = await _client.rpc(
      'get_reorder_source',
      params: {'p_order_id': orderId, 'p_store_id': AppConfig.storeId},
    );

    final rawLines = data is List ? data : const <dynamic>[];
    final lines = <ReorderLine>[];
    var unavailable = 0;
    var adjusted = 0;

    for (final raw in rawLines) {
      if (raw is! Map) {
        unavailable++;
        continue;
      }

      final row = Map<String, dynamic>.from(raw);
      final rawProduct = row['products'];
      if (rawProduct is! Map) {
        unavailable++;
        continue;
      }

      final product = Product.fromMap(Map<String, dynamic>.from(rawProduct));
      final requested = (row['quantity'] as num?)?.toInt() ?? 0;
      if (!product.isAvailable ||
          product.stockQty < product.minQty ||
          requested <= 0) {
        unavailable++;
        continue;
      }

      var quantity = requested > product.stockQty
          ? product.stockQty
          : requested;

      if (product.qtyStep > 1) {
        quantity -= quantity % product.qtyStep;
      }

      if (quantity < product.minQty) {
        unavailable++;
        continue;
      }

      if (quantity != requested) adjusted++;
      lines.add(ReorderLine(product: product, quantity: quantity));
    }

    return ReorderResult(
      lines: lines,
      unavailableCount: unavailable,
      adjustedCount: adjusted,
    );
  }

  static Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    if (_userId == null || token.trim().isEmpty) return;
    try {
      await _client.rpc(
        'register_push_token',
        params: {
          'p_store_id': AppConfig.storeId,
          'p_token': token.trim(),
          'p_platform': platform,
        },
      );
    } catch (_) {
      // Push registration is non-critical for shopping and remains optional
      // until the migration/Firebase production configuration is deployed.
    }
  }

  static Future<List<Map<String, dynamic>>> fetchNotifications({
    int limit = 60,
  }) async {
    final userId = _userId;
    if (userId == null) return const [];

    try {
      final data = await _client
          .from('customer_notifications')
          .select('id,order_id,type,title,body,data,read_at,created_at')
          .eq('customer_id', userId)
          .eq('store_id', AppConfig.storeId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<int> unreadNotificationCount() async {
    final userId = _userId;
    if (userId == null) return 0;

    try {
      final data = await _client
          .from('customer_notifications')
          .select('id')
          .eq('customer_id', userId)
          .eq('store_id', AppConfig.storeId)
          .isFilter('read_at', null)
          .limit(100);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final userId = _userId;
    if (userId == null || notificationId.isEmpty) return;

    try {
      await _client
          .from('customer_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId)
          .eq('customer_id', userId);
    } catch (_) {
      // Reading a notification must never block navigation to an order.
    }
  }
}
