import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/growth_service.dart';
import 'order_tracking_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await GrowthService.fetchNotifications();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل الإشعارات الآن');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isNotEmpty && item['read_at'] == null) {
      await GrowthService.markNotificationRead(id);
      if (mounted) {
        setState(() => item['read_at'] = DateTime.now().toIso8601String());
      }
    }

    final orderId = item['order_id']?.toString() ?? '';
    if (!mounted || orderId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId)),
    );
  }

  String _date(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    return DateFormat('dd/MM • HH:mm', 'ar').format(date);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'offer':
        return Icons.local_offer_outlined;
      case 'order_status':
        return Icons.local_shipping_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 100),
                        Icon(
                          Icons.notifications_none,
                          size: 58,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error ?? 'ما عندك إشعارات جديدة',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final unread = item['read_at'] == null;
                        return Material(
                          color: unread
                              ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.07)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _open(item),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.10),
                                    child: Icon(
                                      _iconFor(item['type']?.toString() ?? ''),
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['title']?.toString() ?? 'تحديث جديد',
                                          style: TextStyle(
                                            fontWeight: unread
                                                ? FontWeight.w900
                                                : FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item['body']?.toString() ?? '',
                                          style: const TextStyle(
                                            color: Color(0xFF6B7280),
                                            height: 1.35,
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        Text(
                                          _date(item['created_at']),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (unread)
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
