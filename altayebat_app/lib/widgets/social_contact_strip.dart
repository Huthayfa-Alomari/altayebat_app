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
      enabled: settings.tiktokUrl.isNotEmpty,
      value: settings.tiktokUrl,
      icon: Icons.music_note_rounded,
      label: 'TikTok',
      foreground: const Color(0xFF111111),
      background: const Color(0xFFF3F3F3),
      provider: 'tiktok',
    );
    add(
      enabled: settings.googleMapsUrl.isNotEmpty,
      value: settings.googleMapsUrl,
      icon: Icons.location_on_rounded,
      label: 'الموقع',
      foreground: const Color(0xFF0B8043),
      background: const Color(0xFFECF8EF),
      provider: 'google_maps',
    );

    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECEBE7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.connect_without_contact_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 7),
              Text(
                'تابعنا وتواصل معنا',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions
                .map((action) => SizedBox(width: 96, child: action))
                .toList(growable: false),
          ),
        ],
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
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foregroundColor, size: 21),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
