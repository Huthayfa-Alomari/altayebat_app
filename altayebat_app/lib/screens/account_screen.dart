import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/analytics_service.dart';
import '../services/customer_support_service.dart';
import '../services/store_settings_service.dart';
import '../settings/app_language.dart';
import '../settings/app_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/altayebat_brand.dart';
import 'customer_auth_screen.dart';
import 'loyalty_screen.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';
import 'referral_screen.dart';
import 'rider_mode_screen.dart';
import 'support_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _name;
  String? _phone;
  bool _loading = true;
  StorePublicSettings _settings = StorePublicSettings.defaults();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;

    try {
      final settings = await StoreSettingsService.load(forceRefresh: true);
      Map<String, dynamic>? row;
      if (user != null) {
        final data = await Supabase.instance.client
            .from('customers')
            .select('name,phone')
            .eq('id', user.id)
            .maybeSingle();
        if (data != null) row = Map<String, dynamic>.from(data);
      }

      if (!mounted) return;
      setState(() {
        _settings = settings;
        _name = (row?['name'] as String?)?.trim();
        _phone = (row?['phone'] as String?)?.trim();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasProfile =>
      (_name?.isNotEmpty ?? false) && (_phone?.isNotEmpty ?? false);

  Future<void> _openSupport() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SupportScreen()));
  }

  Future<void> _openExternal(String url, String source) async {
    final opened = await CustomerSupportService.openWeb(url, source: source);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط.')));
    }
  }

  Future<void> _requestAccountDeletion() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل الدخول أولًا لطلب حذف الحساب.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب حذف الحساب'),
        content: const Text(
          'سنراجع الطلب ونتحقق من الهوية قبل حذف البيانات. قد نحتفظ بسجلات الطلبات أو الفواتير التي يلزم الاحتفاظ بها قانونيًا أو محاسبيًا. هل تريد إرسال الطلب؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'request_account_deletion',
        params: {'p_store_id': AppConfig.storeId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل طلب حذف الحساب. سنتحقق منه ونعالجه.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر إرسال طلب الحذف الآن. تواصل مع خدمة العملاء.'),
        ),
      );
    }
  }

  Future<void> _shareApp() async {
    final link = _settings.playStoreUrl.isNotEmpty
        ? _settings.playStoreUrl
        : _settings.appStoreUrl;
    final text = link.isEmpty
        ? _settings.shareMessage
        : '${_settings.shareMessage}\n$link';

    await AnalyticsService.track(
      'app_share',
      entityType: 'app',
      entityId: 'whatsapp',
    );

    final opened = await launchUrl(
      Uri.https('wa.me', '/', {'text': text}),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر فتح المشاركة.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preferences = context.watch<AppPreferences>();
    String t(String ar, String en) => AppLanguage.text(context, ar, en);
    return Scaffold(
      appBar: AppBar(title: Text(t('حسابي', 'My account'))),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: const AltayebatBrandLogo(markSize: 118),
            ),
            const SizedBox(height: 14),
            _profileCard(),
            const SizedBox(height: 20),
            _AccountSectionTitle(
              title: t('التفضيلات', 'Preferences'),
              icon: Icons.tune_rounded,
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('اللغة', 'Language'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar', label: Text('العربية')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {preferences.locale.languageCode},
                      onSelectionChanged: (selection) =>
                          preferences.setLanguage(selection.first),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: Text(t('الوضع الداكن', 'Dark mode')),
                      value: preferences.darkMode,
                      onChanged: preferences.setDarkMode,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _AccountSectionTitle(
              title: t('التسوق والحساب', 'Shopping & account'),
              icon: Icons.shopping_bag_outlined,
            ),
            const SizedBox(height: 10),
            _AccountTile(
              icon: Icons.receipt_long_outlined,
              title: t('طلباتي', 'My orders'),
              subtitle: t(
                'تابع الطلبات الحالية والسابقة',
                'Track current and past orders',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.notifications_none_rounded,
              title: t('الإشعارات', 'Notifications'),
              subtitle: t('العروض وتحديثات الطلب', 'Offers and order updates'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
            if (_settings.featureLoyalty)
              _AccountTile(
                icon: Icons.workspace_premium_outlined,
                title: t('مكافآتي', 'My rewards'),
                subtitle: t(
                  'تابع السلال والمكافآت المتاحة',
                  'See available rewards',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoyaltyScreen()),
                ),
              ),
            if (_settings.featureReferral)
              _AccountTile(
                icon: Icons.card_giftcard_rounded,
                title: t('ادعُ صديقك', 'Invite a friend'),
                subtitle: t(
                  'شارك كودك واكسبوا المكافآت',
                  'Share your code and earn rewards',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReferralScreen()),
                ),
              ),
            const SizedBox(height: 10),
            _AccountSectionTitle(
              title: t('المساعدة والتطبيق', 'Help & app'),
              icon: Icons.support_agent_outlined,
            ),
            const SizedBox(height: 10),
            _AccountTile(
              icon: Icons.support_agent_rounded,
              title: t('خدمة العملاء', 'Customer support'),
              subtitle: t(
                'مشكلة طلب، توصيل، دفع أو استفسار',
                'Orders, delivery, payments and questions',
              ),
              onTap: _openSupport,
            ),
            _AccountTile(
              icon: Icons.share_rounded,
              title: t('شارك التطبيق', 'Share the app'),
              subtitle: t(
                'شارك أسواق الطيبات مع أصدقائك',
                'Share Altayebat with friends',
              ),
              onTap: _shareApp,
            ),
            if (_settings.websiteEnabled && _settings.websiteUrl.isNotEmpty)
              _AccountTile(
                icon: Icons.language_rounded,
                title: t('الموقع الإلكتروني', 'Website'),
                subtitle: t('افتح موقع المتجر', 'Open the store website'),
                onTap: () => _openExternal(_settings.websiteUrl, 'website'),
              ),
            if (_settings.privacyPolicyUrl.isNotEmpty)
              _AccountTile(
                icon: Icons.privacy_tip_outlined,
                title: t('سياسة الخصوصية', 'Privacy policy'),
                subtitle: t('كيف نتعامل مع بياناتك', 'How we handle your data'),
                onTap: () =>
                    _openExternal(_settings.privacyPolicyUrl, 'privacy_policy'),
              ),
            if (_settings.termsUrl.isNotEmpty)
              _AccountTile(
                icon: Icons.gavel_outlined,
                title: t('الشروط والأحكام', 'Terms & conditions'),
                subtitle: t(
                  'شروط استخدام التطبيق والطلبات',
                  'App and order terms',
                ),
                onTap: () => _openExternal(_settings.termsUrl, 'terms'),
              ),
            if (Supabase.instance.client.auth.currentUser != null)
              _AccountTile(
                icon: Icons.delete_outline_rounded,
                title: t('حذف الحساب وبياناتي', 'Delete my account'),
                subtitle: t(
                  'إرسال طلب موثّق لحذف الحساب والبيانات المرتبطة',
                  'Request deletion of your account and data',
                ),
                onTap: _requestAccountDeletion,
              ),
            _AccountTile(
              icon: Icons.delivery_dining_rounded,
              title: t('وضع المندوب', 'Courier mode'),
              subtitle: t(
                'دخول المندوب وإدارة طلبات التوصيل',
                'Courier sign in and deliveries',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RiderModeScreen()),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.skyBlueDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(
                        'بياناتك تستخدم فقط لتجهيز الطلب والتوصيل ومتابعة الحالة.',
                        'Your information is used to prepare, deliver and track your order.',
                      ),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: _loading
          ? const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            )
          : Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasProfile
                            ? _name!
                            : AppLanguage.text(
                                context,
                                'أنت تتصفح كضيف',
                                'Browsing as a guest',
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hasProfile
                            ? _phone!
                            : AppLanguage.text(
                                context,
                                'تصفح وتسوق براحتك، وسنطلب OTP فقط عند إتمام الشراء',
                                'Browse freely. We will verify your phone at checkout.',
                              ),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _editProfile,
                  child: Text(
                    _hasProfile
                        ? AppLanguage.text(context, 'تعديل', 'Edit')
                        : AppLanguage.text(context, 'تسجيل / دخول', 'Sign in'),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CustomerAuthScreen(returnAfterSuccess: true),
      ),
    );
    if (mounted) await _loadProfile();
  }
}

class _AccountSectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _AccountSectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, color: AppColors.skyBlueDark, size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = icon.codePoint.isEven
        ? AppColors.primary
        : AppColors.skyBlueDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_back_ios_new_rounded
                      : Icons.arrow_forward_ios_rounded,
                  color: colors.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
