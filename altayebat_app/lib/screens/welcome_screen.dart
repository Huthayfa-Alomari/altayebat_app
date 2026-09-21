import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'customer_auth_screen.dart';
import 'storefront_root_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _loading = false;

  Future<void> _finishEntryChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('entry_choice_completed', true);
  }

  Future<void> _browseAsGuest() async {
    if (_loading) return;
    setState(() => _loading = true);
    await _finishEntryChoice();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StorefrontRootScreen()),
    );
  }

  Future<void> _signIn() async {
    if (_loading) return;

    final authenticated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CustomerAuthScreen(returnAfterSuccess: true),
      ),
    );

    if (authenticated != true || !mounted) return;

    setState(() => _loading = true);
    await _finishEntryChoice();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StorefrontRootScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -70,
              right: -50,
              child: _Glow(
                size: 210,
                color: AppColors.primary.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              bottom: 90,
              left: -70,
              child: _Glow(
                size: 230,
                color: AppColors.skyBlue.withValues(alpha: 0.12),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.navy.withValues(alpha: 0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryDark,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              Icons.shopping_basket_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'أهلًا بك في أسواق الطيبات',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'تصفح الأقسام والعروض وأضف للسلة براحتك بدون تسجيل. نطلب رقم الموبايل وOTP فقط عندما تقرر إتمام الشراء.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loading ? null : _browseAsGuest,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: const Icon(Icons.storefront_outlined),
                          label: const Text(
                            'تصفح كضيف',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _signIn,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            side: const BorderSide(
                              color: AppColors.skyBlueDark,
                            ),
                            foregroundColor: AppColors.skyBlueDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text(
                            'تسجيل / دخول',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _BenefitRow(
                          icon: Icons.shopping_cart_checkout_rounded,
                          text: 'السلة تبقى كما هي عند التسجيل وقت الدفع',
                        ),
                        const SizedBox(height: 8),
                        const _BenefitRow(
                          icon: Icons.sms_outlined,
                          text: 'OTP لتأكيد الرقم وحماية الطلبات',
                        ),
                        const SizedBox(height: 8),
                        const _BenefitRow(
                          icon: Icons.lock_outline_rounded,
                          text: 'لا نطلب كلمة مرور',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.skySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.skyBlueDark, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
