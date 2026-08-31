import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class CallScreen extends StatefulWidget {
  final String? orderId;

  const CallScreen({super.key, this.orderId});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _loading = false;
  String? _requestedType;
  String? _error;

  Future<void> _requestCall(String type) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await SupabaseService.requestCall(
        type: type,
        orderId: widget.orderId,
      );
      if (!mounted) return;
      setState(() => _requestedType = type);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر إرسال طلب التواصل. تأكد من الإنترنت وجرب مرة ثانية.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تواصل مع موظف')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _requestedType != null
              ? _waitingState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'كيف بدك تتواصل مع موظف الطيبات؟',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'أرسل الطلب، والموظف رح يتواصل معك حسب النوع اللي اخترته.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _optionCard(
                      icon: Icons.call_outlined,
                      title: 'مكالمة صوتية',
                      subtitle: 'اطلب من الموظف يتصل فيك صوتيًا',
                      onTap: () => _requestCall('voice'),
                    ),
                    const SizedBox(height: 12),
                    _optionCard(
                      icon: Icons.videocam_outlined,
                      title: 'مكالمة فيديو',
                      subtitle: 'اطلب مساعدة مرئية باختيار المنتجات',
                      onTap: () => _requestCall('video'),
                    ),
                    const SizedBox(height: 12),
                    _optionCard(
                      icon: Icons.chat_bubble_outline,
                      title: 'شات مباشر',
                      subtitle: 'أرسل طلب محادثة كتابية مع الموظف',
                      onTap: () => _requestCall('chat'),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _optionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: _loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
              const Icon(Icons.arrow_back_ios, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waitingState() {
    const typeLabels = {
      'voice': 'المكالمة الصوتية',
      'video': 'مكالمة الفيديو',
      'chat': 'الشات',
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.support_agent,
            color: AppColors.primary,
            size: 34,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'طلب ${typeLabels[_requestedType] ?? 'التواصل'} وصل للموظف',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'رح يتم التواصل معك بمجرد ما يكون الموظف متاح.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
