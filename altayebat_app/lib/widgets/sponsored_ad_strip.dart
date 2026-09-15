import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';

class SponsoredAdStrip extends StatefulWidget {
  const SponsoredAdStrip({super.key});

  @override
  State<SponsoredAdStrip> createState() => _SponsoredAdStripState();
}

class _SponsoredAdStripState extends State<SponsoredAdStrip> {
  late final Future<List<_SponsoredAd>> _adsFuture = _loadAds();
  final Set<String> _trackedImpressions = <String>{};

  Future<List<_SponsoredAd>> _loadAds() async {
    try {
      final rows = await Supabase.instance.client
          .from('storefront_banners')
          .select(
            'id,title,subtitle,image_url,target_type,target_value,'
            'starts_at,ends_at,sort_order',
          )
          .eq('store_id', AppConfig.storeId)
          .eq('position', 'sponsor')
          .eq('is_active', true)
          .order('sort_order')
          .limit(12);

      final now = DateTime.now().toUtc();
      return (rows as List)
          .map(
            (row) =>
                _SponsoredAd.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .where((ad) => ad.isLiveAt(now))
          .toList(growable: false);
    } catch (_) {
      return const <_SponsoredAd>[];
    }
  }

  void _trackVisibleAds(List<_SponsoredAd> ads) {
    for (final ad in ads) {
      if (!_trackedImpressions.add(ad.id)) continue;
      unawaited(
        AnalyticsService.track(
          'ad_impression',
          entityType: 'sponsored_banner',
          entityId: ad.id,
          properties: {'title': ad.title},
        ),
      );
    }
  }

  Future<void> _open(_SponsoredAd ad) async {
    await AnalyticsService.track(
      'ad_click',
      entityType: 'sponsored_banner',
      entityId: ad.id,
      properties: {'title': ad.title, 'target_type': ad.targetType},
    );

    if (ad.targetType != 'url') return;
    final uri = Uri.tryParse(ad.targetValue ?? '');
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_SponsoredAd>>(
      future: _adsFuture,
      builder: (context, snapshot) {
        final ads = snapshot.data ?? const <_SponsoredAd>[];
        if (ads.isEmpty) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) => _trackVisibleAds(ads));

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: SizedBox(
            height: 94,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ads.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final ad = ads[index];
                return SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.84,
                  child: Material(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(ad),
                      child: Row(
                        children: [
                          if (ad.imageUrl != null)
                            SizedBox(
                              width: 104,
                              height: double.infinity,
                              child: Image.network(
                                ad.imageUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 420,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (_, __, ___) => _fallbackImage(),
                              ),
                            )
                          else
                            _fallbackImage(),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.skySoft,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Text(
                                      'إعلان ممول',
                                      style: TextStyle(
                                        color: AppColors.navy,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ad.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (ad.subtitle != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      ad.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (ad.targetType == 'url')
                            const Padding(
                              padding: EdgeInsetsDirectional.only(end: 10),
                              child: Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackImage() {
    return Container(
      width: 104,
      height: double.infinity,
      color: AppColors.skySoft,
      alignment: Alignment.center,
      child: const Icon(
        Icons.campaign_rounded,
        color: AppColors.skyBlueDark,
        size: 34,
      ),
    );
  }
}

class _SponsoredAd {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? targetType;
  final String? targetValue;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const _SponsoredAd({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.targetType,
    this.targetValue,
    this.startsAt,
    this.endsAt,
  });

  factory _SponsoredAd.fromMap(Map<String, dynamic> map) {
    String? clean(dynamic value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    DateTime? date(dynamic value) =>
        DateTime.tryParse(value?.toString() ?? '')?.toUtc();

    return _SponsoredAd(
      id: clean(map['id']) ?? '',
      title: clean(map['title']) ?? 'إعلان',
      subtitle: clean(map['subtitle']),
      imageUrl: clean(map['image_url']),
      targetType: clean(map['target_type']),
      targetValue: clean(map['target_value']),
      startsAt: date(map['starts_at']),
      endsAt: date(map['ends_at']),
    );
  }

  bool isLiveAt(DateTime now) {
    if (id.isEmpty) return false;
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }
}
