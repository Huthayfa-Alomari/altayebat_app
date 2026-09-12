import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/product.dart';

class TerminalService {
  TerminalService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<bool> currentUserIsStoreAdmin() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final row = await _client
        .from('store_admins')
        .select('store_id')
        .eq('user_id', userId)
        .eq('store_id', AppConfig.storeId)
        .maybeSingle();
    return row != null;
  }

  static Stream<List<Map<String, dynamic>>> watchOrders() {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('store_id', AppConfig.storeId)
        .order('created_at', ascending: false)
        .limit(100);
  }

  static Future<Map<String, dynamic>> fetchOrder(String orderId) async {
    final order = await _client
        .from('orders')
        .select(
          'id, status, total, created_at, payment_method, payment_status, payment_reference, customers(name, phone)',
        )
        .eq('id', orderId)
        .eq('store_id', AppConfig.storeId)
        .maybeSingle();

    if (order == null) throw StateError('الطلب غير موجود');

    final items = await _client
        .from('order_items')
        .select(
          'id, quantity, unit_price, sale_type_snapshot, base_unit_snapshot, inventory_scale_snapshot, display_unit_price_snapshot, products(name)',
        )
        .eq('order_id', orderId);

    return <String, dynamic>{
      ...Map<String, dynamic>.from(order),
      'items': (items as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false),
    };
  }

  static Future<void> updateOrderStatus(String orderId, String status) async {
    const allowed = {'preparing', 'out_for_delivery', 'delivered', 'cancelled'};
    if (!allowed.contains(status)) {
      throw ArgumentError.value(status, 'status', 'حالة غير مدعومة');
    }

    await _client.rpc(
      'admin_update_order_status',
      params: <String, dynamic>{
        'p_order_id': orderId,
        'p_store_id': AppConfig.storeId,
        'p_new_status': status,
      },
    );
  }

  static Future<Product?> lookupProductByBarcode(String barcode) async {
    final normalized = barcode.trim();
    if (normalized.isEmpty) return null;

    final row = await _client
        .from('products')
        .select()
        .eq('store_id', AppConfig.storeId)
        .eq('barcode', normalized)
        .maybeSingle();

    if (row == null) return null;
    return Product.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<void> setProductStock(
    Product product, {
    required double displayQuantity,
  }) async {
    if (!displayQuantity.isFinite || displayQuantity < 0) {
      throw ArgumentError('المخزون غير صالح');
    }

    final atomic = (displayQuantity * product.inventoryScale).round();
    await _client
        .from('products')
        .update(<String, dynamic>{
          'stock_qty': atomic,
          'is_available': atomic > 0,
        })
        .eq('id', product.id)
        .eq('store_id', AppConfig.storeId);
  }
}
