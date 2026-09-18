import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/analytics_service.dart';
import '../services/store_settings_service.dart';
import '../theme/app_theme.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _codeController = TextEditingController();
  Map<String, dynamic>? _state;
  StorePublicSettings _settings = StorePublicSettings.defaults();
  bool _loading = true;
  bool _applying = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        Supabase.instance.client.rpc(
          'get_my_referral_state',
          params: {'p_store_id': AppConfig.storeId},
        ),
        StoreSettingsService.load(),
      ]);
      if (!mounted) return;
      setState(() {
        _state = Map<String, dynamic>.from(results[0] as Map);
        _settings = results[1] as StorePublicSettings;
      });
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل نظام الدعوات الآن.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'أدخل كود الدعوة أولًا.');
      return;
    }
    setState(() {
      _applying = true;
      _error = null;
      _success = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'apply_referral_code',
        params: {'p_store_id': AppConfig.storeId, 'p_code': code},
      );
      if (!mounted) return;
      setState(
        () => _success = 'تم قبول كود الدعوة. تُضاف المكافأة بعد أول طلب مؤهل.',
      );
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _friendlyError(PostgrestException error) {
    final message = error.message.toUpperCase();
    if (message.contains('REFERRAL_DISABLED')) {
      return 'نظام الدعوات غير مفعّل حاليًا.';
    }
    if (message.contains('INVALID_REFERRAL_CODE')) {
      return 'كود الدعوة غير صحيح.';
    }
    if (message.contains('SELF_REFERRAL')) {
      return 'لا يمكنك استخدام كودك الشخصي.';
    }
    if (message.contains('REFERRAL_ALREADY_APPLIED')) {
      return 'تم استخدام كود دعوة لهذا الحساب مسبقًا.';
    }
    if (message.contains('REFERRAL_NEW_CUSTOMERS_ONLY')) {
      return 'كود الدعوة متاح قبل أول طلب مكتمل فقط.';
    }
    if (message.contains('PROFILE_REQUIRED')) {
      return 'أكمل بيانات حسابك أولًا.';
    }
    return 'تعذر تنفيذ العملية الآن.';
  }

  String get _code => _state?['code']?.toString() ?? '';
  bool get _enabled => _state?['enabled'] == true;
  bool get _alreadyJoined => _state?['joined_with_code'] is Map;

  Future<void> _copyCode() async {
    if (_code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ كود الدعوة.')));
  }

  Future<void> _shareWhatsApp() async {
    if (_code.isEmpty || !_enabled) return;
    final rewardTitle = _state?['reward_title']?.toString() ?? 'مكافأة';
    final message =
        '${_settings.shareMessage}\nكود دعوتي: $_code\n$rewardTitle بعد أول طلب مؤهل.';
    await AnalyticsService.track(
      'referral_share',
      entityType: 'referral',
      entityId: 'whatsapp',
    );
    final uri = Uri.https('wa.me', '/', {'text': message});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  int _intValue(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('ادعُ صديقك')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) _messageBox(_error!, false),
                  if (_success != null) _messageBox(_success!, true),
                  _hero(),
                  const SizedBox(height: 14),
                  _stats(),
                  const SizedBox(height: 14),
                  if (!_enabled)
                    _messageBox(
                      'نظام Referral موجود لكنه غير مفعّل حاليًا من إدارة المتجر.',
                      false,
                    ),
                  if (_enabled && !_alreadyJoined) ...[
                    const SizedBox(height: 14),
                    _applyCard(),
                  ],
                  if (_alreadyJoined) ...[
                    const SizedBox(height: 14),
                    _messageBox(
                      'تم ربط حسابك بدعوة. المكافأة تُحتسب تلقائيًا بعد الطلب المؤهل.',
                      true,
                    ),
                  ],
                  const SizedBox(height: 14),
                  _terms(),
                ],
              ),
            ),
    );
  }

  Widget _hero() {
    final title = _state?['program_name']?.toString() ?? 'ادعُ صديقك';
    final reward = _state?['reward_title']?.toString() ?? 'مكافأة دعوة';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.card_giftcard_rounded,
            size: 42,
            color: AppColors.primary,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            reward,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.skySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'كود دعوتك',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _code.isEmpty ? '—' : _code,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _code.isEmpty ? null : _copyCode,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('نسخ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _enabled && _code.isNotEmpty
                      ? _shareWhatsApp
                      : null,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    return Row(
      children: [
        Expanded(child: _stat('الدعوات', _intValue(_state?['invites_count']))),
        const SizedBox(width: 10),
        Expanded(
          child: _stat('مكتملة', _intValue(_state?['rewarded_invites_count'])),
        ),
      ],
    );
  }

  Widget _stat(String label, int value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'عندك كود من صديق؟',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 5),
          const Text(
            'أضفه قبل أول طلب مكتمل حتى تستفيد من المكافأة.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'مثال: A1B2C3D4',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _applying ? null : _applyCode,
            child: _applying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('استخدام الكود'),
          ),
        ],
      ),
    );
  }

  Widget _terms() {
    final minOrder = _state?['min_first_order_total']?.toString() ?? '0';
    final terms = _state?['terms_text']?.toString() ?? '';
    final referrerRewards = _state?['referrer_reward_count']?.toString() ?? '0';
    final referredRewards = _state?['referred_reward_count']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'الحد الأدنى للطلب المؤهل: $minOrder د.أ\n'
        'مكافأة صاحب الدعوة: $referrerRewards • مكافأة الصديق: $referredRewards\n'
        '$terms',
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.6,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _messageBox(String text, bool success) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFEAF8EF) : const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: success ? const Color(0xFF176B37) : AppColors.primaryDark,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
