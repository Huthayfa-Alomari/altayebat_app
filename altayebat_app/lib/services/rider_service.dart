import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class RiderService {
  RiderService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static bool get hasPhoneSession =>
      (currentUser?.phone ?? '').trim().isNotEmpty;

  static String normalizeJordanPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (RegExp(r'^9627[0-9]{8}$').hasMatch(digits)) return '+$digits';
    if (RegExp(r'^07[0-9]{8}$').hasMatch(digits)) {
      return '+962${digits.substring(1)}';
    }
    if (RegExp(r'^7[0-9]{8}$').hasMatch(digits)) return '+962$digits';
    throw const FormatException('أدخل رقم أردني صحيح مثل 0791234567');
  }

  static Future<String> requestOtp(String phone) async {
    final normalized = normalizeJordanPhone(phone);
    await _client.auth.signInWithOtp(phone: normalized, shouldCreateUser: true);
    return normalized;
  }

  static Future<void> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final normalized = normalizeJordanPhone(phone);
    final cleanCode = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanCode.length < 4) {
      throw const FormatException('أدخل رمز التحقق كاملًا');
    }

    final response = await _client.auth.verifyOTP(
      phone: normalized,
      token: cleanCode,
      type: OtpType.sms,
    );
    if (response.user == null || (response.user?.phone ?? '').isEmpty) {
      throw StateError('تعذر تسجيل دخول المندوب');
    }
  }

  static Future<Map<String, dynamic>?> me() async {
    if (!hasPhoneSession) return null;
    final data = await _client.rpc('rider_me');
    if (data == null || data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    String? vehicleType,
    String? vehiclePlate,
  }) async {
    if (!hasPhoneSession) throw StateError('PHONE_AUTH_REQUIRED');
    final cleanName = name.trim();
    if (cleanName.length < 2) {
      throw const FormatException('أدخل اسم المندوب');
    }

    final data = await _client.rpc(
      'rider_register',
      params: {
        'p_store_id': AppConfig.storeId,
        'p_name': cleanName,
        'p_vehicle_type': _blankToNull(vehicleType),
        'p_vehicle_plate': _blankToNull(vehiclePlate),
      },
    );
    if (data is! Map) throw StateError('تعذر إنشاء حساب المندوب');
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> setAvailability(String status) async {
    final normalized = status.trim().toLowerCase();
    if (!const {'available', 'break', 'offline'}.contains(normalized)) {
      throw ArgumentError('حالة المندوب غير صالحة');
    }
    final data = await _client.rpc(
      'rider_set_availability',
      params: {'p_status': normalized},
    );
    if (data is! Map) throw StateError('تعذر تحديث حالة المندوب');
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> heartbeat() async {
    final data = await _client.rpc('rider_heartbeat');
    if (data is! Map) throw StateError('تعذر تحديث اتصال المندوب');
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> deliveryTasks() async {
    final data = await _client.rpc('rider_my_delivery_tasks');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> deliveryAction({
    required String orderId,
    required String action,
  }) async {
    final id = orderId.trim();
    if (id.isEmpty) throw ArgumentError('رقم الطلب غير صالح');
    final normalized = action.trim().toLowerCase();
    if (!const {'pickup', 'start', 'complete'}.contains(normalized)) {
      throw ArgumentError('إجراء التوصيل غير صالح');
    }

    final data = await _client.rpc(
      'rider_delivery_action',
      params: {'p_order_id': id, 'p_action': normalized},
    );
    if (data is! Map) throw StateError('تعذر تحديث الطلب');
    return Map<String, dynamic>.from(data);
  }

  static Future<void> pushLocation({
    required String orderId,
    required Position position,
  }) async {
    await _client.rpc(
      'rider_push_location',
      params: {
        'p_order_id': orderId,
        'p_lat': position.latitude,
        'p_lng': position.longitude,
        'p_accuracy_m': position.accuracy,
        'p_speed_mps': position.speed.isFinite && position.speed >= 0
            ? position.speed
            : null,
        'p_heading_deg': position.heading.isFinite && position.heading >= 0
            ? position.heading % 360
            : null,
      },
    );
  }

  static Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    final clean = token.trim();
    if (clean.isEmpty || !hasPhoneSession) return;
    await _client.rpc(
      'register_rider_push_token',
      params: {'p_token': clean, 'p_platform': platform.trim().toLowerCase()},
    );
  }

  static Future<void> unregisterPushToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty || !hasPhoneSession) return;
    await _client.rpc(
      'unregister_rider_push_token',
      params: {'p_token': clean},
    );
  }

  static Future<bool> syncPushToken() async {
    if (!hasPhoneSession || Firebase.apps.isEmpty) return false;

    final rider = await me();
    if (rider == null ||
        rider['approval_status']?.toString() != 'approved' ||
        rider['is_active'] != true) {
      return false;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) return false;

    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    await registerPushToken(token: token, platform: platform);
    return true;
  }

  static Future<void> signOutToAnonymous() async {
    if (hasPhoneSession && Firebase.apps.isNotEmpty) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.trim().isNotEmpty) {
          await unregisterPushToken(token);
        }
      } catch (_) {
        // Sign-out must remain available even if FCM is temporarily unavailable.
      }
    }

    await _client.auth.signOut();
    final response = await _client.auth.signInAnonymously();
    if (response.user == null) {
      throw StateError('تعذر بدء جلسة التسوق');
    }
  }

  static String friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('PHONE_AUTH_REQUIRED')) {
      return 'يجب تسجيل الدخول برقم الهاتف أولًا.';
    }
    if (raw.contains('RIDER_NOT_REGISTERED')) {
      return 'حساب المندوب غير مسجل بعد.';
    }
    if (raw.contains('RIDER_NOT_APPROVED')) {
      return 'حساب المندوب بانتظار الاعتماد أو موقوف.';
    }
    if (raw.contains('RIDER_ALREADY_LINKED_TO_ANOTHER_STORE')) {
      return 'هذا الحساب مربوط بفرع آخر.';
    }
    if (raw.contains('PAYMENT_NOT_CONFIRMED')) {
      return 'لا يمكن بدء التوصيل قبل تأكيد الدفع.';
    }
    if (raw.contains('ORDER_NOT_ASSIGNED_TO_RIDER')) {
      return 'هذا الطلب غير مسند إليك.';
    }
    if (raw.contains('ORDER_NOT_READY_FOR_PICKUP')) {
      return 'الطلب غير جاهز للاستلام.';
    }
    if (raw.contains('ORDER_NOT_READY_FOR_DELIVERY')) {
      return 'الطلب غير جاهز لبدء التوصيل.';
    }
    if (raw.contains('ORDER_NOT_OUT_FOR_DELIVERY')) {
      return 'ابدأ التوصيل أولًا.';
    }
    if (raw.contains('INVALID_COORDINATES')) {
      return 'تعذر إرسال موقع GPS الحالي.';
    }
    if (raw.contains('Token has expired') || raw.contains('otp_expired')) {
      return 'انتهت صلاحية رمز التحقق. اطلب رمزًا جديدًا.';
    }
    if (raw.contains('invalid') && raw.toLowerCase().contains('otp')) {
      return 'رمز التحقق غير صحيح.';
    }
    if (error is FormatException) return error.message;
    return 'تعذر تنفيذ العملية. تحقق من الإنترنت وحاول مرة ثانية.';
  }

  static String? _blankToNull(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}
