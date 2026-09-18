import 'package:url_launcher/url_launcher.dart';

import 'analytics_service.dart';
import 'store_settings_service.dart';

class CustomerSupportService {
  CustomerSupportService._();

  static String normalizeJordanPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0') && digits.length >= 9) {
      digits = '962${digits.substring(1)}';
    }
    return digits;
  }

  static String supportWhatsAppNumber(StorePublicSettings settings) {
    final preferred = settings.supportWhatsappNumber.trim();
    return normalizeJordanPhone(
      preferred.isNotEmpty ? preferred : settings.whatsappNumber,
    );
  }

  static String supportPhoneNumber(StorePublicSettings settings) {
    final preferred = settings.supportPhone.trim();
    return normalizeJordanPhone(
      preferred.isNotEmpty ? preferred : settings.whatsappNumber,
    );
  }

  static Future<bool> openWhatsApp(
    StorePublicSettings settings, {
    required String message,
    String source = 'general',
  }) async {
    final phone = supportWhatsAppNumber(settings);
    if (phone.isEmpty) return false;

    await AnalyticsService.track(
      'support_click',
      entityType: 'support',
      entityId: 'whatsapp_$source',
    );

    return launchUrl(
      Uri.https('wa.me', '/$phone', {'text': message}),
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<bool> call(
    StorePublicSettings settings, {
    String source = 'general',
  }) async {
    final phone = supportPhoneNumber(settings);
    if (phone.isEmpty) return false;

    await AnalyticsService.track(
      'support_click',
      entityType: 'support',
      entityId: 'call_$source',
    );

    return launchUrl(
      Uri.parse('tel:+$phone'),
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<bool> openWeb(String rawUrl, {required String source}) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;

    await AnalyticsService.track(
      'support_click',
      entityType: 'legal',
      entityId: source,
    );

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
