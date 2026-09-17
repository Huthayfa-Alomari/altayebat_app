import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/store_settings_service.dart';
import '../theme/app_theme.dart';

class StoreAnnouncementBanner extends StatelessWidget {
  final StorePublicSettings settings;

  const StoreAnnouncementBanner({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    if (!settings.announcementEnabled ||
        (settings.announcementTitle.isEmpty &&
            settings.announcementBody.isEmpty)) {
      return const SizedBox.shrink();
    }

    final (background, foreground, icon) = switch (settings.announcementStyle) {
      'sale' => (
          AppColors.primary.withValues(alpha: 0.08),
          AppColors.primaryDark,
          Icons.local_offer_outlined,
        ),
      'warning' => (
          const Color(0xFFFFF4E5),
          const Color(0xFF8A4B08),
          Icons.warning_amber_rounded,
        ),
      _ => (
          AppColors.skySoft,
          AppColors.skyBlueDark,
          Icons.campaign_outlined,
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (settings.announcementTitle.isNotEmpty)
                  Text(
                    settings.announcementTitle,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                if (settings.announcementBody.isNotEmpty)
                  Text(
                    settings.announcementBody,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          if (settings.announcementActionLabel.isNotEmpty &&
              settings.announcementActionUrl.isNotEmpty)
            TextButton(
              onPressed: () async {
                final uri = Uri.tryParse(settings.announcementActionUrl);
                if (uri == null || !uri.hasScheme) return;
                await AnalyticsService.track(
                  'announcement_click',
                  entityType: 'store_announcement',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Text(settings.announcementActionLabel),
            ),
        ],
      ),
    );
  }
}
