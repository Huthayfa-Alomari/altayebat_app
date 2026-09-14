import 'package:flutter/material.dart';

import '../models/store_offer.dart';
import '../services/growth_service.dart';
import '../services/storefront_settings_service.dart';
import '../theme/app_theme.dart';

class StorefrontShell extends StatefulWidget {
  final Widget child;

  const StorefrontShell({super.key, required this.child});

  @override
  State<StorefrontShell> createState() => _StorefrontShellState();
}

class _StorefrontShellState extends State<StorefrontShell> {
  StorefrontSettings _settings = const StorefrontSettings.fallback();
  List<StoreOffer> _offers = const [];
  Map<String, dynamic>? _loyalty;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      StorefrontSettingsService.fetch(),
      GrowthService.fetchActiveOffers(),
      GrowthService.fetchLoyaltyStatus(),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as StorefrontSettings;
      _offers = results[1] as List<StoreOffer>;
      _loyalty = results[2] as Map<String, dynamic>?;
      _ready = true;
    });
  }

  int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final showBanner =
        _ready && _settings.showOffersSection && _offers.isNotEmpty;
    final baskets = _intValue(_loyalty?['baskets_current']);
    final rewards = _intValue(_loyalty?['rewards_available']);

    // Keep the storefront clean for brand-new shoppers. Loyalty appears after
    // the customer earns the first basket, or immediately when a reward exists.
    final showLoyalty = _ready && _loyalty != null && (baskets > 0 || rewards > 0);
    final hasTopContent = showBanner || showLoyalty;

    final storefront = hasTopContent
        ? MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          )
        : widget.child;

    return Material(
      color: AppColors.background,
      child: Column(
        children: [
          if (hasTopContent)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  children: [
                    if (showBanner)
                      _OfferHero(settings: _settings, offer: _offers.first),
                    if (showBanner && showLoyalty) const SizedBox(height: 7),
                    if (showLoyalty) _LoyaltyStrip(status: _loyalty!),
                  ],
                ),
              ),
            ),
          Expanded(child: storefront),
        ],
      ),
    );
  }
}

class _LoyaltyStrip extends StatelessWidget {
  final Map<String, dynamic> status;

  const _LoyaltyStrip({required this.status});

  int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _intValue(status['baskets_current']);
    final required = _intValue(status['baskets_required']).clamp(1, 20);
    final rewards = _intValue(status['rewards_available']);
    final remaining = _intValue(status['orders_remaining']);
    final title = status['program_name']?.toString().trim();
    final rewardTitle = status['reward_title']?.toString().trim();
    final progress = (current / required).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.skyBlue.withValues(alpha: 0.09),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.skySoft,
              shape: BoxShape.circle,
            ),
            child: const Text('🧺', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title?.isNotEmpty == true ? title! : 'مكافآت الطيبات',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      rewards > 0 ? 'هدية جاهزة 🎁' : '$current/$required',
                      style: const TextStyle(
                        color: AppColors.skyBlueDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (rewards > 0)
                  Text(
                    rewardTitle?.isNotEmpty == true
                        ? rewardTitle!
                        : 'التوصيل علينا بالطلب القادم',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: AppColors.skySoft,
                      color: AppColors.skyBlueDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    remaining <= 1
                        ? 'بقي طلب واحد للمكافأة'
                        : 'بقي $remaining طلبات للمكافأة',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferHero extends StatelessWidget {
  final StorefrontSettings settings;
  final StoreOffer offer;

  const _OfferHero({required this.settings, required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFFE31E24), Color(0xFFEF5F68), AppColors.skyBlue],
          stops: [0, 0.58, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.skyBlue.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -28,
            top: -42,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.11),
              ),
            ),
          ),
          PositionedDirectional(
            end: 66,
            bottom: -48,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'عروض الطيبات',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'خصم ${offer.discountPercent}%',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        settings.offerBannerTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        settings.offerBannerSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.17),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
