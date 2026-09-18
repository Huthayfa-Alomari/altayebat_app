import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/store_settings_service.dart';
import '../theme/app_theme.dart';

class SocialContactStrip extends StatelessWidget {
  final StorePublicSettings settings;

  const SocialContactStrip({super.key, required this.settings});

  Future<void> _open(
    BuildContext context, {
    required Uri uri,
    required String provider,
  }) async {
    await AnalyticsService.track(
      'social_click',
      entityType: 'social',
      entityId: provider,
    );

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط. حاول مرة ثانية.')),
    );
  }

  Uri? _webUri(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];

    void add({
      required bool enabled,
      required String value,
      required IconData icon,
      required String label,
      required Color foreground,
      required Color background,
      required String provider,
    }) {
      final uri = _webUri(value);
      if (!enabled || uri == null) return;

      actions.add(
        _SocialButton(
          icon: icon,
          label: label,
          foregroundColor: foreground,
          backgroundColor: background,
          onTap: () => _open(context, uri: uri, provider: provider),
        ),
      );
    }

    add(
      enabled: settings.facebookEnabled,
      value: settings.facebookUrl,
      icon: Icons.facebook,
      label: 'فيسبوك',
      foreground: const Color(0xFF1877F2),
      background: const Color(0xFFEFF5FF),
      provider: 'facebook',
    );

    add(
      enabled: settings.instagramEnabled,
      value: settings.instagramUrl,
      icon: Icons.camera_alt_rounded,
      label: 'إنستغرام',
      foreground: const Color(0xFFC13584),
      background: const Color(0xFFFFF0F7),
      provider: 'instagram',
    );

    final whatsappPhone = settings.whatsappNumber.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (settings.featureWhatsapp &&
        settings.whatsappEnabled &&
        whatsappPhone.isNotEmpty) {
      final whatsappUri = Uri.https('wa.me', '/$whatsappPhone', {
        'text': settings.whatsappDefaultMessage,
      });

      actions.add(
        _SocialButton(
          icon: Icons.chat_rounded,
          label: 'واتساب',
          foregroundColor: const Color(0xFF128C7E),
          backgroundColor: const Color(0xFFECFBF5),
          onTap: () => _open(context, uri: whatsappUri, provider: 'whatsapp'),
        ),
      );
    }

    add(
      enabled: settings.tiktokEnabled && settings.tiktokUrl.isNotEmpty,
      value: settings.tiktokUrl,
      icon: Icons.music_note_rounded,
      label: 'TikTok',
      foreground: const Color(0xFF111111),
      background: const Color(0xFFF3F3F3),
      provider: 'tiktok',
    );

    add(
      enabled: settings.googleMapsEnabled && settings.googleMapsUrl.isNotEmpty,
      value: settings.googleMapsUrl,
      icon: Icons.location_on_rounded,
      label: 'الموقع',
      foreground: const Color(0xFF0B8043),
      background: const Color(0xFFECF8EF),
      provider: 'google_maps',
    );

    add(
      enabled: settings.websiteEnabled && settings.websiteUrl.isNotEmpty,
      value: settings.websiteUrl,
      icon: Icons.language_rounded,
      label: 'الموقع',
      foreground: AppColors.navy,
      background: AppColors.skySoft,
      provider: 'website',
    );

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: actions,
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Tooltip(
              message: label,
              child: Icon(icon, color: foregroundColor, size: 23),
            ),
          ),
        ),
      ),
    );
  }
}
