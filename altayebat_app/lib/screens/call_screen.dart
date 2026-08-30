import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

// شاشة اختيار نوع التواصل مع موظف المول.
// ملاحظة تقنية: الاتصال الفعلي (صوت/فيديو) بيحتاج دمج SDK متخصص
// متل Agora أو Stream — هاي الشاشة جاهزة لتستقبل ذاك الدمج، وهلأ
// بتسجل طلب التواصل بقاعدة البيانات (call_requests) والموظف يشوفه
// من لوحة التحكم ويرد.
class CallScreen extends StatefulWidget {
  final String? orderId;

  const CallScreen({super.key, this.orderId});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _loading = false;
  String? _requestedType;

  Future<void> _requestCall(String type) async {
    setState(() => _loading = true);
    try {
      await SupabaseService.requestCall(
        type: type,
        orderId: widget.orderId,
      );
      setState(() => _requestedType = type);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تواصل مع موظف')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _requestedType != null
            ? _waitingState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'كيف بدك تتواصل مع موظف الطيبات؟',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _optionCard(
                    icon: Icons.call_outlined,
                    title: 'مكالمة صوتية',
                    subtitle: 'اتصال صوتي مباشر مع موظف',
                    onTap: () => _requestCall('voice'),
                  ),
                  const SizedBox(height: 12),
                  _optionCard(
                    icon: Icons.videocam_outlined,
                    title: 'مكالمة فيديو',
                    subtitle: 'يشوفك الموظف ويساعدك تختار',
                    onTap: () => _requestCall('video'),
                  ),
                  const SizedBox(height: 12),
                  _optionCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'شات مباشر',
                    subtitle: 'راسل الموظف كتابياً',
                    onTap: () => _requestCall('chat'),
                  ),
                ],
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
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 20),
        const Text(
          'طلبك وصل لموظف الطيبات، بانتظار الرد...',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}