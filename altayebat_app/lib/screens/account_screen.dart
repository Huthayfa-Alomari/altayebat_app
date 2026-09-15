import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'customer_auth_screen.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';
import 'rider_mode_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _name;
  String? _phone;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('customers')
          .select('name,phone')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('حسابي')),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _profileCard(),
            const SizedBox(height: 18),
            _AccountTile(
              icon: Icons.receipt_long_outlined,
              title: 'طلباتي',
              subtitle: 'تابع الطلبات الحالية والسابقة',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.notifications_none_rounded,
              title: 'الإشعارات',
              subtitle: 'العروض وتحديثات الطلب',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.delivery_dining_rounded,
              title: 'وضع المندوب',
              subtitle: 'دخول المندوب وإدارة طلبات التوصيل',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RiderModeScreen()),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.skySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.skyBlueDark,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'بياناتك تستخدم فقط لتجهيز الطلب والتوصيل ومتابعة الحالة.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
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
                  decoration: const BoxDecoration(
                    color: AppColors.skySoft,
                    shape: BoxShape.circle,
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
                        _hasProfile ? _name! : 'أهلًا بك في أسواق الطيبات',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hasProfile
                            ? _phone!
                            : 'أكمل بياناتك لتسريع إتمام الطلب',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _editProfile,
                  child: Text(_hasProfile ? 'تعديل' : 'إكمال'),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.softSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textSecondary,
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
