import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/social_config.dart';
import '../theme/app_theme.dart';

class SocialContactStrip extends StatelessWidget {
  const SocialContactStrip({super.key});

  Future<void> _openUri(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح الرابط. حاول مرة ثانية.')),
    );
  }

  Future<void> _openConfiguredUrl(
    BuildContext context, {
    required String rawUrl,
    required String platformName,
  }) async {
    final value = rawUrl.trim();
    final uri = Uri.tryParse(value);

    if (value.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('رابط $platformName الرسمي غير مضاف بعد.')),
      );
      return;
    }

    await _openUri(context, uri);
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final phone = SocialConfig.whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم واتساب غير مضاف بعد.')),
      );
      return;
    }

    final uri = Uri.https('wa.me', '/$phone', <String, String>{
      'text': 'مرحباً أسواق الطيبات، أحتاج مساعدة بخصوص طلبي.',
    });
    await _openUri(context, uri);
  }

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: _SocialButton(
                  icon: Icons.facebook,
                  label: 'فيسبوك',
                  foregroundColor: const Color(0xFF1877F2),
                  backgroundColor: const Color(0xFFEFF5FF),
                  onTap: () => _openConfiguredUrl(
                    context,
                    rawUrl: SocialConfig.facebookUrl,
                    platformName: 'فيسبوك',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SocialButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'إنستغرام',
                  foregroundColor: const Color(0xFFC13584),
                  backgroundColor: const Color(0xFFFFF0F7),
                  onTap: () => _openConfiguredUrl(
                    context,
                    rawUrl: SocialConfig.instagramUrl,
                    platformName: 'إنستغرام',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SocialButton(
                  icon: Icons.chat_rounded,
                  label: 'واتساب',
                  foregroundColor: const Color(0xFF128C7E),
                  backgroundColor: const Color(0xFFECFBF5),
                  onTap: () => _openWhatsApp(context),
                ),
              ),
            ],
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
