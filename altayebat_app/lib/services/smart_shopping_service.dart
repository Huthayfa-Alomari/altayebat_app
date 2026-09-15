import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/product.dart';
import 'analytics_service.dart';

class SmartShoppingResult {
  final String message;
  final List<SmartShoppingItem> items;
  final double totalEstimate;
  final String provider;
  final double? budget;

  const SmartShoppingResult({
    required this.message,
    required this.items,
    required this.totalEstimate,
    required this.provider,
    this.budget,
  });

  factory SmartShoppingResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] is List ? map['items'] as List : const [];
    return SmartShoppingResult(
      message: map['message']?.toString() ?? 'هذه أفضل الاقتراحات المتاحة.',
      items: rawItems
          .whereType<Map>()
          .map(
            (raw) => SmartShoppingItem.fromMap(Map<String, dynamic>.from(raw)),
          )
          .toList(growable: false),
      totalEstimate: (map['total_estimate'] as num?)?.toDouble() ?? 0,
      provider: map['provider']?.toString() ?? 'catalog_fallback',
      budget: (map['budget'] as num?)?.toDouble(),
    );
  }
}

class SmartShoppingItem {
  final Product product;
  final int quantity;
  final String reason;

  const SmartShoppingItem({
    required this.product,
    required this.quantity,
    required this.reason,
  });

  factory SmartShoppingItem.fromMap(Map<String, dynamic> map) {
    return SmartShoppingItem(
      product: Product.fromMap(map),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      reason: map['reason']?.toString() ?? 'اقتراح ذكي',
    );
  }
}

class SmartShoppingService {
  SmartShoppingService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<SmartShoppingResult> ask(String prompt) async {
    final normalized = prompt.trim();
    if (normalized.length < 3) {
      throw StateError('اكتب طلبك بتفاصيل أكثر شوي');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('يجب تسجيل الدخول لاستخدام المساعد الذكي');
    }

    await AnalyticsService.track(
      'ai_assistant_request',
      entityType: 'ai_assistant',
      properties: {'prompt_length': normalized.length},
    );

    final response = await _client.functions.invoke(
      'smart-shopping-assistant',
      body: {'store_id': AppConfig.storeId, 'prompt': normalized},
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError('تعذر تجهيز الاقتراحات الآن. حاول مرة ثانية.');
    }

    final data = response.data;
    if (data is! Map) {
      throw StateError('استجابة المساعد غير صالحة');
    }

    final result = SmartShoppingResult.fromMap(Map<String, dynamic>.from(data));
    await AnalyticsService.track(
      'ai_assistant_result',
      entityType: 'ai_assistant',
      properties: {
        'items': result.items.length,
        'provider': result.provider,
        'total_estimate': result.totalEstimate,
      },
    );
    return result;
  }
}
