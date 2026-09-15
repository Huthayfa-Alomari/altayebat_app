import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class AnalyticsService {
  AnalyticsService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static final String _sessionId = _newSessionId();

  static String _newSessionId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random.secure().nextInt(1 << 32).toRadixString(36);
    return '$now-$random';
  }

  static Future<void> track(
    String eventName, {
    String? entityType,
    String? entityId,
    Map<String, dynamic> properties = const {},
  }) async {
    if (_client.auth.currentUser == null || eventName.trim().isEmpty) return;

    try {
      await _client.rpc(
        'track_app_event',
        params: {
          'p_store_id': AppConfig.storeId,
          'p_event_name': eventName.trim(),
          'p_entity_type': entityType,
          'p_entity_id': entityId,
          'p_properties': properties,
          'p_session_id': _sessionId,
        },
      );
    } catch (_) {
      // Analytics must never block shopping or navigation.
    }
  }
}
