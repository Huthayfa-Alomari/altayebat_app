import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class StorefrontSettings {
  final bool showOffersSection;
  final String offerBannerTitle;
  final String offerBannerSubtitle;

  const StorefrontSettings({
    required this.showOffersSection,
    required this.offerBannerTitle,
    required this.offerBannerSubtitle,
  });

  const StorefrontSettings.fallback()
    : showOffersSection = true,
      offerBannerTitle = 'عروض مميزة اليوم',
      offerBannerSubtitle = 'وفر أكثر مع عروض أسواق الطيبات';

  factory StorefrontSettings.fromMap(Map<String, dynamic>? row) {
    if (row == null) return const StorefrontSettings.fallback();
    return StorefrontSettings(
      showOffersSection: row['show_offers_section'] as bool? ?? true,
      offerBannerTitle:
          row['offer_banner_title']?.toString().trim().isNotEmpty == true
          ? row['offer_banner_title'].toString().trim()
          : 'عروض مميزة اليوم',
      offerBannerSubtitle:
          row['offer_banner_subtitle']?.toString().trim().isNotEmpty == true
          ? row['offer_banner_subtitle'].toString().trim()
          : 'وفر أكثر مع عروض أسواق الطيبات',
    );
  }
}

class StorefrontSettingsService {
  StorefrontSettingsService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<StorefrontSettings> fetch() async {
    try {
      final row = await _client
          .from('storefront_settings')
          .select(
            'show_offers_section,offer_banner_title,offer_banner_subtitle',
          )
          .eq('store_id', AppConfig.storeId)
          .maybeSingle();
      return StorefrontSettings.fromMap(
        row == null ? null : Map<String, dynamic>.from(row),
      );
    } catch (_) {
      // Keep the storefront usable if the migration has not reached an
      // environment yet. The admin toggle becomes authoritative once deployed.
      return const StorefrontSettings.fallback();
    }
  }
}
