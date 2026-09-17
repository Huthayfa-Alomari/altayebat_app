import 'package:flutter/material.dart';

import '../services/customer_support_service.dart';
import '../services/store_settings_service.dart';
import '../theme/app_theme.dart';

class SupportScreen extends StatefulWidget {
  final String? orderId;

  const SupportScreen({super.key, this.orderId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  StorePublicSettings _settings = StorePublicSettings.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await StoreSettingsService.load(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  String get _shortOrderId {
    final id = widget.orderId?.replaceAll('-', '') ?? '';
    if (id.isEmpty) return '';
    return id.substring(0, id.length >= 8 ? 8 : id.length).toUpperCase();
  }

  String _message(String topic) {
    final orderPart = _shortOrderId.isEmpty ? '' : ' للطلب #$_shortOrderId';
    return 'مرحباً ${_settings.storeName}، $topic$orderPart.';
  }

  Future<void> _openWhatsApp(String topic) async {
    final opened = await CustomerSupportService.openWhatsApp(
      _settings,
      message: _message(topic),
      source: topic,
    );
    if (!opened && mounted) {
      _show('تعذر فتح واتساب.');
    }
  }

  Future<void> _call() async {
    final opened = await CustomerSupportService.call(
      _settings,
      source: widget.orderId == null ? 'support' : 'order',
    );
    if (!opened && mounted) {
      _show('رقم خدمة العملاء غير متاح حاليًا.');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('خدمة العملاء')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.support_agent_rounded,
                        size: 42,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _settings.storeName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (_settings.supportHoursText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _settings.supportHoursText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (_shortOrderId.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'الطلب #$_shortOrderId',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SupportAction(
                  icon: Icons.receipt_long_outlined,
                  title: 'مشكلة بطلب',
                  subtitle: 'تأخير، نقص، خطأ أو تعديل على الطلب',
                  onTap: () => _openWhatsApp('عندي مشكلة'),
                ),
                _SupportAction(
                  icon: Icons.inventory_2_outlined,
                  title: 'استفسار عن منتج',
                  subtitle: 'سعر، توفر، حجم أو بديل',
                  onTap: () => _openWhatsApp('عندي استفسار عن منتج'),
                ),
                _SupportAction(
                  icon: Icons.local_shipping_outlined,
                  title: 'استفسار عن التوصيل',
                  subtitle: 'الوقت، الموقع أو المندوب',
                  onTap: () => _openWhatsApp('أحتاج مساعدة بخصوص التوصيل'),
                ),
                _SupportAction(
                  icon: Icons.payments_outlined,
                  title: 'مشكلة بالدفع',
                  subtitle: 'بطاقة، CliQ أو حالة الدفع',
                  onTap: () => _openWhatsApp('أحتاج مساعدة بخصوص الدفع'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _call,
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('اتصال بخدمة العملاء'),
                ),
              ],
            ),
    );
  }
}

class _SupportAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.08),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}
