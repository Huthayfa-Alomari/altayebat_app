import 'package:flutter/material.dart';

import '../services/growth_service.dart';
import '../theme/app_theme.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final status = await GrowthService.fetchLoyaltyStatus(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final current = _int(status?['baskets_current']);
    final required = _int(status?['baskets_required']).clamp(1, 100);
    final rewards = _int(status?['rewards_available']);
    final lifetime = _int(status?['lifetime_baskets']);
    final title = status?['program_name']?.toString() ?? 'مكافآت الطيبات';
    final rewardTitle = status?['reward_title']?.toString() ?? 'مكافأة';
    final progress = (current / required).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('مكافآتي')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (status == null)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'برنامج المكافآت غير مفعّل حاليًا.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.navy, AppColors.skyBlueDark],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'اجمع $required سلال مؤهلة لتحصل على $rewardTitle.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 18),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(99),
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$current / $required',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _card(
                            icon: Icons.card_giftcard_rounded,
                            label: 'مكافآت جاهزة',
                            value: rewards,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _card(
                            icon: Icons.shopping_basket_outlined,
                            label: 'سلال مدى الحياة',
                            value: lifetime,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _card({
    required IconData icon,
    required String label,
    required int value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 7),
          Text(
            '$value',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
