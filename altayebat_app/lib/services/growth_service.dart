import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/product.dart';
import '../models/reorder_result.dart';
import '../models/store_offer.dart';
import 'storefront_settings_service.dart';

class GrowthService {
  GrowthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static String? get _userId => _client.auth.currentUser?.id;

  static const Duration _offerCacheTtl = Duration(seconds: 45);
  static const Duration _offerRefreshThrottle = Duration(minutes: 1);
  static const Duration _loyaltyCacheTtl = Duration(seconds: 30);
  static const Duration _notificationCountTtl = Duration(seconds: 10);

  static List<StoreOffer>? _offersCache;
  static DateTime? _offersCachedAt;
  static Future<List<StoreOffer>>? _offersInFlight;
  static DateTime? _lastOfferRefresh;
  static Future<void>? _offerRefreshInFlight;

  static final Map<String, Map<String, dynamic>?> _loyaltyCache = {};
  static final Map<String, DateTime> _loyaltyCachedAt = {};
  static final Map<String, Future<Map<String, dynamic>?>> _loyaltyInFlight = {};

  static final Map<String, int> _notificationCountCache = {};
  static final Map<String, DateTime> _notificationCountCachedAt = {};
  static final Map<String, Future<int>> _notificationCountInFlight = {};

  static bool _fresh(DateTime? savedAt, Duration ttl) {
    return savedAt != null && DateTime.now().difference(savedAt) < ttl;
  }

  static Future<void> refreshExpiredOffers({bool force = false}) async {
    if (!force && _fresh(_lastOfferRefresh, _offerRefreshThrottle)) return;
    final pending = _offerRefreshInFlight;
    if (pending != null) return pending;

    final future = _runOfferRefresh();
    _offerRefreshInFlight = future;
    try {
      await future;
    } finally {
      _lastOfferRefresh = DateTime.now();
      if (identical(_offerRefreshInFlight, future)) {
        _offerRefreshInFlight = null;
      }
    }
  }

  static Future<void> _runOfferRefresh() async {
    try {
      await _client.rpc(
        'refresh_expired_offers',
        params: {'p_store_id': AppConfig.storeId},
      );
    } catch (_) {
      // Backward compatible while the growth migration is not deployed yet.
    }
  }

  static Future<List<StoreOffer>> fetchActiveOffers({
    bool forceRefresh = false,
  }) async {
    final settings = await StorefrontSettingsService.fetch(
      forceRefresh: forceRefresh,
    );
    if (!settings.showOffersSection) return const <StoreOffer>[];

    if (!forceRefresh &&
        _offersCache != null &&
        _fresh(_offersCachedAt, _offerCacheTtl)) {
      return _offersCache!;
    }
    if (!forceRefresh && _offersInFlight != null) return _offersInFlight!;

    final future = _loadActiveOffers(forceRefresh: forceRefresh);
    _offersInFlight = future;
    try {
      final value = await future;
      _offersCache = value;
      _offersCachedAt = DateTime.now();
      return value;
    } finally {
      if (identical(_offersInFlight, future)) _offersInFlight = null;
    }
  }

  static Future<List<StoreOffer>> _loadActiveOffers({
    required bool forceRefresh,
  }) async {
    await refreshExpiredOffers(force: forceRefresh);
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
      return _offersCache ?? const <StoreOffer>[];
    }
  }

  static Future<Map<String, dynamic>?> fetchLoyaltyStatus({
    bool forceRefresh = false,
  }) async {
    final userId = _userId;
    if (userId == null) return null;

    if (!forceRefresh &&
        _loyaltyCache.containsKey(userId) &&
        _fresh(_loyaltyCachedAt[userId], _loyaltyCacheTtl)) {
      return _loyaltyCache[userId];
    }
    final pending = _loyaltyInFlight[userId];
    if (!forceRefresh && pending != null) return pending;

    final future = _loadLoyaltyStatus(userId);
    _loyaltyInFlight[userId] = future;
    try {
      final value = await future;
      _loyaltyCache[userId] = value;
      _loyaltyCachedAt[userId] = DateTime.now();
      return value;
    } finally {
      if (identical(_loyaltyInFlight[userId], future)) {
        _loyaltyInFlight.remove(userId);
      }
    }
  }

  static Future<Map<String, dynamic>?> _loadLoyaltyStatus(String userId) async {
    try {
      final data = await _client.rpc(
        'get_my_loyalty_status',
        params: {'p_store_id': AppConfig.storeId},
      );
      if (data is! Map) return null;
      final status = Map<String, dynamic>.from(data);
      if (status['enabled'] != true) return null;
      return status;
    } catch (_) {
      // Keep old deployments working until the loyalty migration is deployed.
      return _loyaltyCache[userId];
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

  static Future<int> unreadNotificationCount({
    bool forceRefresh = false,
  }) async {
    final userId = _userId;
    if (userId == null) return 0;

    if (!forceRefresh &&
        _notificationCountCache.containsKey(userId) &&
        _fresh(_notificationCountCachedAt[userId], _notificationCountTtl)) {
      return _notificationCountCache[userId]!;
    }
    final pending = _notificationCountInFlight[userId];
    if (!forceRefresh && pending != null) return pending;

    final future = _loadUnreadNotificationCount(userId);
    _notificationCountInFlight[userId] = future;
    try {
      final value = await future;
      _notificationCountCache[userId] = value;
      _notificationCountCachedAt[userId] = DateTime.now();
      return value;
    } finally {
      if (identical(_notificationCountInFlight[userId], future)) {
        _notificationCountInFlight.remove(userId);
      }
    }
  }

  static Future<int> _loadUnreadNotificationCount(String userId) async {
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
      return _notificationCountCache[userId] ?? 0;
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
      _notificationCountCache.remove(userId);
      _notificationCountCachedAt.remove(userId);
    } catch (_) {
      // Reading a notification must never block navigation to an order.
    }
  }

  static void invalidateStorefrontCaches() {
    _offersCache = null;
    _offersCachedAt = null;
    _lastOfferRefresh = null;
    _loyaltyCache.clear();
    _loyaltyCachedAt.clear();
    _notificationCountCache.clear();
    _notificationCountCachedAt.clear();
    StorefrontSettingsService.invalidate();
  }
}
