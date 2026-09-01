import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class CallScreen extends StatefulWidget {
  final String? orderId;

  const CallScreen({super.key, this.orderId});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _loading = true;
  String? _phone;
  String _storeName = 'أسواق الطيبات';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    try {
      final config = await SupabaseService.getStoreContactConfig();
      if (!mounted) return;
      setState(() {
        _storeName = (config['name'] as String?)?.trim().isNotEmpty == true
            ? config['name'] as String
            : 'أسواق الطيبات';
        _phone = (config['phone'] as String?)?.trim();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل بيانات التواصل. حاول مرة ثانية.';
      });
    }
  }

  String? _jordanWhatsAppNumber(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00962')) digits = digits.substring(2);
    if (digits.startsWith('962')) return digits;
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits.isEmpty ? null : '962$digits';
  }

  Future<void> _launchPhone() async {
    final phone = _phone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showLaunchError('تعذر فتح تطبيق الاتصال');
    }
  }

  Future<void> _launchWhatsApp() async {
    final whatsapp = _jordanWhatsAppNumber(_phone);
    if (whatsapp == null) return;
    final orderText = widget.orderId == null || widget.orderId!.isEmpty
        ? ''
        : ' بخصوص طلبي #${_shortOrderId(widget.orderId!)}';
    final message = 'مرحبًا، بدي أتواصل مع $_storeName$orderText';
    final uri = Uri.parse(
      'https://wa.me/$whatsapp?text=${Uri.encodeComponent(message)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showLaunchError('تعذر فتح واتساب');
    }
  }

  void _showLaunchError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _shortOrderId(String id) {
    if (id.length <= 8) return id.toUpperCase();
    return id.substring(0, 8).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = _phone != null && _phone!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('تواصل مع المول')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تواصل مباشرة مع $_storeName',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'للاستفسار عن طلبك أو أي منتج، اختار الطريقة الأنسب إلك.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _notice(_error!, Colors.red.shade50, Colors.red.shade800),
                    ],
                    if (!hasPhone) ...[
                      const SizedBox(height: 16),
                      _notice(
                        'رقم المول سيتم تفعيله عند اعتماد النسخة النهائية. خيارات الاتصال وواتساب جاهزة للربط مباشرة.',
                        AppColors.primary.withValues(alpha: 0.06),
                        AppColors.textPrimary,
                      ),
                    ],
                    const SizedBox(height: 22),
                    _optionCard(
                      icon: Icons.call_outlined,
                      title: 'اتصال عادي',
                      subtitle: hasPhone
                          ? 'اتصل بالمول مباشرة'
                          : 'يتم تفعيله عند إضافة رقم المول',
                      enabled: hasPhone,
                      onTap: _launchPhone,
                    ),
                    const SizedBox(height: 12),
                    _optionCard(
                      icon: Icons.chat_outlined,
                      title: 'واتساب',
                      subtitle: hasPhone
                          ? 'افتح محادثة واتساب مع المول'
                          : 'يتم تفعيله عند إضافة رقم المول',
                      enabled: hasPhone,
                      onTap: _launchWhatsApp,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'التواصل يتم من خلال رقم المول الرسمي فقط.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _notice(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: foreground),
      ),
    );
  }

  Widget _optionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled ? Icons.arrow_back_ios_new : Icons.lock_outline,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
