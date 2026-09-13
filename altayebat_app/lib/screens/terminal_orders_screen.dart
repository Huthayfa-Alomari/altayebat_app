import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sunmi_printer_service.dart';
import '../services/terminal_receipt.dart';
import '../services/terminal_service.dart';
import 'terminal_order_detail_screen.dart';

class TerminalOrdersScreen extends StatefulWidget {
  const TerminalOrdersScreen({super.key});

  @override
  State<TerminalOrdersScreen> createState() => _TerminalOrdersScreenState();
}

class _TerminalOrdersScreenState extends State<TerminalOrdersScreen> {
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _orders = const [];
  final Set<String> _seenOrderIds = <String>{};
  final Set<String> _printedOrderIds = <String>{};
  bool _initialized = false;
  bool _autoPrint = false;
  bool _showCompleted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscription = TerminalService.watchOrders().listen(
      (orders) {
        final normalized = orders
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        final incomingIds = normalized
            .map((order) => order['id']?.toString())
            .whereType<String>()
            .toSet();

        if (_initialized) {
          final newPending = normalized
              .where((order) {
                final id = order['id']?.toString();
                return id != null &&
                    !_seenOrderIds.contains(id) &&
                    order['status']?.toString() == 'pending';
              })
              .toList(growable: false);

          if (newPending.isNotEmpty) {
            SystemSound.play(SystemSoundType.alert);
            if (_autoPrint) {
              for (final order in newPending) {
                final id = order['id']?.toString();
                if (id != null) unawaited(_printNewOrder(id));
              }
            }
          }
        } else {
          _initialized = true;
        }

        _seenOrderIds.addAll(incomingIds);
        if (!mounted) return;
        setState(() {
          _orders = normalized;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = 'تعذر استقبال الطلبات لحظيًا.');
      },
    );
  }

  Future<void> _printNewOrder(String orderId) async {
    if (_printedOrderIds.contains(orderId)) return;
    try {
      if (!await SunmiPrinterService.isPrinterReady()) return;
      final order = await TerminalService.fetchOrder(orderId);
      await SunmiPrinterService.printReceipt(
        receipt: TerminalReceipt.build(order),
        qr: orderId,
      );
      _printedOrderIds.add(orderId);
    } catch (_) {
      // The order remains visible and can always be printed manually.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _orders
        .where((order) {
          if (_showCompleted) return true;
          final status = order['status']?.toString();
          return status != 'delivered' && status != 'cancelled';
        })
        .toList(growable: false);

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'طباعة الطلب الجديد تلقائيًا',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('يعمل عند اتصال طابعة SUNMI فقط.'),
                  value: _autoPrint,
                  onChanged: (value) => setState(() => _autoPrint = value),
                ),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('الطلبات النشطة'),
                      selected: !_showCompleted,
                      onSelected: (_) => setState(() => _showCompleted = false),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('كل الطلبات'),
                      selected: _showCompleted,
                      onSelected: (_) => setState(() => _showCompleted = true),
                    ),
                    const Spacer(),
                    Text(
                      '${visible.length} طلب',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF1F2),
            padding: const EdgeInsets.all(10),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9F1239)),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? const _EmptyOrders()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final order = visible[index];
                    return _OrderCard(
                      order: order,
                      onTap: () async {
                        final id = order['id']?.toString();
                        if (id == null) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                TerminalOrderDetailScreen(orderId: id),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;

  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = order['id']?.toString() ?? '';
    final shortId = id.length >= 8 ? id.substring(0, 8).toUpperCase() : id;
    final status = order['status']?.toString() ?? 'pending';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final createdAt = DateTime.tryParse(
      order['created_at']?.toString() ?? '',
    )?.toLocal();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: _statusColor(status),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'طلب #$shortId',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '${total.toStringAsFixed(2)} د.أ',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _paymentLabel(order['payment_method']?.toString()),
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        if (createdAt != null)
                          Text(
                            '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status) => switch (status) {
    'pending' => const Color(0xFFD97706),
    'preparing' => const Color(0xFF2563EB),
    'out_for_delivery' => const Color(0xFF7C3AED),
    'delivered' => const Color(0xFF15803D),
    'cancelled' => const Color(0xFF6B7280),
    _ => const Color(0xFF374151),
  };

  static String _statusLabel(String status) => switch (status) {
    'pending' => 'جديد',
    'preparing' => 'قيد التجهيز',
    'out_for_delivery' => 'بالتوصيل',
    'delivered' => 'تم التسليم',
    'cancelled' => 'ملغي',
    _ => status,
  };

  static String _paymentLabel(String? method) => switch (method) {
    'cash' => 'كاش',
    'cliq' => 'CliQ',
    'card' => 'بطاقة',
    final value => value ?? '—',
  };
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 58, color: Color(0xFF9CA3AF)),
            SizedBox(height: 12),
            Text(
              'ما في طلبات حاليًا',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 5),
            Text(
              'الطلبات الجديدة ستظهر هنا لحظيًا.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
