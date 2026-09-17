import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class StorePublicSettings {
  final String facebookUrl;
  final String instagramUrl;
  final String tiktokUrl;
  final String websiteUrl;
  final String googleMapsUrl;
  final bool facebookEnabled;
  final bool instagramEnabled;
  final String whatsappNumber;
  final bool whatsappEnabled;
  final String whatsappDefaultMessage;
  final String supportPhone;
  final String supportWhatsappNumber;
  final String supportHoursText;
  final String privacyPolicyUrl;
  final String termsUrl;
  final String playStoreUrl;
  final String appStoreUrl;
  final String storeStatus;
  final String statusMessage;
  final bool allowScheduledOrdersWhenClosed;
  final bool announcementEnabled;
  final String announcementTitle;
  final String announcementBody;
  final String announcementActionLabel;
  final String announcementActionUrl;
  final String announcementStyle;
  final bool featureAi;
  final bool featureOffers;
  final bool featureLoyalty;
  final bool featureAds;
  final bool featureCall;
  final bool featureWhatsapp;
  final bool featureReorder;
  final bool featureReferral;
  final bool maintenanceCheckout;
  final bool maintenancePayments;
  final bool maintenanceDelivery;
  final String welcomeText;
  final String shareMessage;

  const StorePublicSettings({
    required this.facebookUrl,
    required this.instagramUrl,
    required this.tiktokUrl,
    required this.websiteUrl,
    required this.googleMapsUrl,
    required this.facebookEnabled,
    required this.instagramEnabled,
    required this.whatsappNumber,
    required this.whatsappEnabled,
    required this.whatsappDefaultMessage,
    required this.supportPhone,
    required this.supportWhatsappNumber,
    required this.supportHoursText,
    required this.privacyPolicyUrl,
    required this.termsUrl,
    required this.playStoreUrl,
    required this.appStoreUrl,
    required this.storeStatus,
    required this.statusMessage,
    required this.allowScheduledOrdersWhenClosed,
    required this.announcementEnabled,
    required this.announcementTitle,
    required this.announcementBody,
    required this.announcementActionLabel,
    required this.announcementActionUrl,
    required this.announcementStyle,
    required this.featureAi,
    required this.featureOffers,
    required this.featureLoyalty,
    required this.featureAds,
    required this.featureCall,
    required this.featureWhatsapp,
    required this.featureReorder,
    required this.featureReferral,
    required this.maintenanceCheckout,
    required this.maintenancePayments,
    required this.maintenanceDelivery,
    required this.welcomeText,
    required this.shareMessage,
  });

  factory StorePublicSettings.defaults() => const StorePublicSettings(
        facebookUrl: '',
        instagramUrl: '',
        tiktokUrl: '',
        websiteUrl: '',
        googleMapsUrl: '',
        facebookEnabled: true,
        instagramEnabled: true,
        whatsappNumber: '962788570246',
        whatsappEnabled: true,
        whatsappDefaultMessage:
            'مرحباً أسواق الطيبات، أحتاج مساعدة بخصوص طلبي.',
        supportPhone: '0788570246',
        supportWhatsappNumber: '',
        supportHoursText: '',
        privacyPolicyUrl: '',
        termsUrl: '',
        playStoreUrl: '',
        appStoreUrl: '',
        storeStatus: 'open',
        statusMessage: '',
        allowScheduledOrdersWhenClosed: false,
        announcementEnabled: false,
        announcementTitle: '',
        announcementBody: '',
        announcementActionLabel: '',
        announcementActionUrl: '',
        announcementStyle: 'info',
        featureAi: true,
        featureOffers: true,
        featureLoyalty: true,
        featureAds: true,
        featureCall: true,
        featureWhatsapp: true,
        featureReorder: true,
        featureReferral: true,
        maintenanceCheckout: false,
        maintenancePayments: false,
        maintenanceDelivery: false,
        welcomeText: 'كل احتياجات البيت بمكان واحد',
        shareMessage: 'حمّل تطبيق أسواق الطيبات وتسوق بسهولة.',
      );

  factory StorePublicSettings.fromMap(Map<String, dynamic> map) {
    final defaults = StorePublicSettings.defaults();
    String text(String key, String fallback) =>
        (map[key]?.toString().trim().isNotEmpty ?? false)
            ? map[key].toString().trim()
            : fallback;
    bool flag(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;

    return StorePublicSettings(
      facebookUrl: text('facebook_url', defaults.facebookUrl),
      instagramUrl: text('instagram_url', defaults.instagramUrl),
      tiktokUrl: text('tiktok_url', defaults.tiktokUrl),
      websiteUrl: text('website_url', defaults.websiteUrl),
      googleMapsUrl: text('google_maps_url', defaults.googleMapsUrl),
      facebookEnabled: flag('facebook_enabled', defaults.facebookEnabled),
      instagramEnabled: flag('instagram_enabled', defaults.instagramEnabled),
      whatsappNumber: text('whatsapp_number', defaults.whatsappNumber),
      whatsappEnabled: flag('whatsapp_enabled', defaults.whatsappEnabled),
      whatsappDefaultMessage: text(
        'whatsapp_default_message',
        defaults.whatsappDefaultMessage,
      ),
      supportPhone: text('support_phone', defaults.supportPhone),
      supportWhatsappNumber: text(
        'support_whatsapp_number',
        defaults.supportWhatsappNumber,
      ),
      supportHoursText: text('support_hours_text', defaults.supportHoursText),
      privacyPolicyUrl: text('privacy_policy_url', defaults.privacyPolicyUrl),
      termsUrl: text('terms_url', defaults.termsUrl),
      playStoreUrl: text('play_store_url', defaults.playStoreUrl),
      appStoreUrl: text('app_store_url', defaults.appStoreUrl),
      storeStatus: text('store_status', defaults.storeStatus),
      statusMessage: text('status_message', defaults.statusMessage),
      allowScheduledOrdersWhenClosed: flag(
        'allow_scheduled_orders_when_closed',
        defaults.allowScheduledOrdersWhenClosed,
      ),
      announcementEnabled: flag(
        'announcement_enabled',
        defaults.announcementEnabled,
      ),
      announcementTitle: text(
        'announcement_title',
        defaults.announcementTitle,
      ),
      announcementBody: text('announcement_body', defaults.announcementBody),
      announcementActionLabel: text(
        'announcement_action_label',
        defaults.announcementActionLabel,
      ),
      announcementActionUrl: text(
        'announcement_action_url',
        defaults.announcementActionUrl,
      ),
      announcementStyle: text(
        'announcement_style',
        defaults.announcementStyle,
      ),
      featureAi: flag('feature_ai', defaults.featureAi),
      featureOffers: flag('feature_offers', defaults.featureOffers),
      featureLoyalty: flag('feature_loyalty', defaults.featureLoyalty),
      featureAds: flag('feature_ads', defaults.featureAds),
      featureCall: flag('feature_call', defaults.featureCall),
      featureWhatsapp: flag('feature_whatsapp', defaults.featureWhatsapp),
      featureReorder: flag('feature_reorder', defaults.featureReorder),
      featureReferral: flag('feature_referral', defaults.featureReferral),
      maintenanceCheckout: flag(
        'maintenance_checkout',
        defaults.maintenanceCheckout,
      ),
      maintenancePayments: flag(
        'maintenance_payments',
        defaults.maintenancePayments,
      ),
      maintenanceDelivery: flag(
        'maintenance_delivery',
        defaults.maintenanceDelivery,
      ),
      welcomeText: text('welcome_text', defaults.welcomeText),
      shareMessage: text('share_message', defaults.shareMessage),
    );
  }

  Map<String, dynamic> toMap() => {
        'facebook_url': facebookUrl,
        'instagram_url': instagramUrl,
        'tiktok_url': tiktokUrl,
        'website_url': websiteUrl,
        'google_maps_url': googleMapsUrl,
        'facebook_enabled': facebookEnabled,
        'instagram_enabled': instagramEnabled,
        'whatsapp_number': whatsappNumber,
        'whatsapp_enabled': whatsappEnabled,
        'whatsapp_default_message': whatsappDefaultMessage,
        'support_phone': supportPhone,
        'support_whatsapp_number': supportWhatsappNumber,
        'support_hours_text': supportHoursText,
        'privacy_policy_url': privacyPolicyUrl,
        'terms_url': termsUrl,
        'play_store_url': playStoreUrl,
        'app_store_url': appStoreUrl,
        'store_status': storeStatus,
        'status_message': statusMessage,
        'allow_scheduled_orders_when_closed': allowScheduledOrdersWhenClosed,
        'announcement_enabled': announcementEnabled,
        'announcement_title': announcementTitle,
        'announcement_body': announcementBody,
        'announcement_action_label': announcementActionLabel,
        'announcement_action_url': announcementActionUrl,
        'announcement_style': announcementStyle,
        'feature_ai': featureAi,
        'feature_offers': featureOffers,
        'feature_loyalty': featureLoyalty,
        'feature_ads': featureAds,
        'feature_call': featureCall,
        'feature_whatsapp': featureWhatsapp,
        'feature_reorder': featureReorder,
        'feature_referral': featureReferral,
        'maintenance_checkout': maintenanceCheckout,
        'maintenance_payments': maintenancePayments,
        'maintenance_delivery': maintenanceDelivery,
        'welcome_text': welcomeText,
        'share_message': shareMessage,
      };
}

class StoreSettingsService {
  StoreSettingsService._();

  static const _cacheKey = 'store_public_settings_v1';
  static StorePublicSettings? _memory;

  static Future<StorePublicSettings> load({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    StorePublicSettings? cached;

    if (!forceRefresh) {
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          cached = StorePublicSettings.fromMap(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
        } catch (_) {
          cached = null;
        }
      }
    }

    try {
      final row = await Supabase.instance.client
          .from('store_public_settings')
          .select()
          .eq('store_id', AppConfig.storeId)
          .maybeSingle();

      if (row != null) {
        final settings = StorePublicSettings.fromMap(
          Map<String, dynamic>.from(row),
        );
        _memory = settings;
        await prefs.setString(_cacheKey, jsonEncode(settings.toMap()));
        return settings;
      }
    } catch (_) {
      // Offline / transient backend error: use the last known good config.
    }

    _memory ??= cached ?? StorePublicSettings.defaults();
    return _memory!;
  }

  static void clearMemory() {
    _memory = null;
  }
}
