import 'package:flutter/material.dart';

import '../services/sunmi_printer_service.dart';
import '../services/terminal_receipt.dart';
import '../services/terminal_service.dart';
import '../widgets/terminal_order_adjustment_sheet.dart';

class TerminalOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const TerminalOrderDetailScreen({super.key, required this.orderId});

  @override
  State<TerminalOrderDetailScreen> createState() =>
      _TerminalOrderDetailScreenState();
}

class _TerminalOrderDetailScreenState extends State<TerminalOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await TerminalService.fetchOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    final order = _order;
    if (order == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ready = await SunmiPrinterService.isPrinterReady();
      if (!ready) throw StateError('طابعة SUNMI غير متصلة.');
      await SunmiPrinterService.printReceipt(
        receipt: TerminalReceipt.build(order),
        qr: order['id']?.toString(),
      );
      if (!mounted) return;
      _show('تمت طباعة الفاتورة.');
    } catch (error) {
      if (!mounted) return;
      _show(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjustOrder() async {
    final order = _order;
    if (order == null || _busy) return;

    final status = order['status']?.toString() ?? 'pending';
    if (status != 'pending' && status != 'preparing') {
      _show('يمكن تعديل الطلب فقط قبل خروجه للتوصيل.');
      return;
    }

    final itemsRaw = order['items'];
    final items = itemsRaw is List
        ? itemsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : <Map<String, dynamic>>[];
    if (items.isEmpty) {
      _show('لا يوجد أصناف قابلة للتعديل.');
      return;
    }

    final adjustment = await showTerminalOrderAdjustmentSheet(context, items);
    if (adjustment == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await TerminalService.adjustOrderItems(
        orderId: widget.orderId,
        reason: adjustment.reason,
        lines: adjustment.lines,
      );
      await _load();
      if (!mounted) return;

      final newTotal = _number(result['new_total']);
      final refundAmount = _number(result['refund_amount']);
      if (refundAmount > 0) {
        _show(
          'تم تعديل الطلب وإبلاغ الزبون. المجموع الجديد ${newTotal.toStringAsFixed(2)} د.أ — راجع رد ${refundAmount.toStringAsFixed(2)} د.أ للبطاقة.',
        );
      } else {
        _show(
          'تم تعديل الطلب وإبلاغ الزبون. المجموع الجديد ${newTotal.toStringAsFixed(2)} د.أ.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = _message(error);
      if (message.contains('ORDER_LOCKED_FOR_ADJUSTMENT')) {
        _show('لا يمكن تعديل الطلب بعد خروجه للتوصيل.');
      } else if (message.contains('EMPTY_ORDER_AFTER_ADJUSTMENT')) {
        _show('لا يمكن حذف كل الأصناف. ألغِ الطلب بدلًا من ذلك.');
      } else if (message.contains('INSUFFICIENT_STOCK_FOR_ADJUSTMENT')) {
        _show('الكمية الجديدة أكبر من المخزون المتوفر.');
      } else {
        _show(message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await TerminalService.updateOrderStatus(widget.orderId, status);
      await _load();
      if (!mounted) return;
      _show('تم تحديث حالة الطلب.');
    } catch (error) {
      if (!mounted) return;
      _show(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final order = _order;
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الطلب')),
        body: Center(child: Text(_error ?? 'تعذر تحميل الطلب.')),
      );
    }

    final id = order['id']?.toString() ?? '';
    final shortId = id.length >= 8 ? id.substring(0, 8).toUpperCase() : id;
    final status = order['status']?.toString() ?? 'pending';
    final total = _number(order['total']);
    final customerRaw = order['customers'];
    final customer = customerRaw is Map
        ? Map<String, dynamic>.from(customerRaw)
        : <String, dynamic>{};
    final itemsRaw = order['items'];
    final items = itemsRaw is List
        ? itemsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : <Map<String, dynamic>>[];
    final canAdjust = status == 'pending' || status == 'preparing';

    return Scaffold(
      appBar: AppBar(
        title: Text('طلب #$shortId'),
        actions: [
          if (canAdjust)
            IconButton(
              tooltip: 'تعديل الأصناف',
              onPressed: _busy ? null : _adjustOrder,
              icon: const Icon(Icons.edit_note_rounded),
            ),
          IconButton(
            tooltip: 'طباعة الفاتورة',
            onPressed: _busy ? null : _print,
            icon: const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            _InfoCard(
              title: 'الزبون',
              rows: [
                ('الاسم', customer['name']?.toString() ?? '—'),
                ('الهاتف', customer['phone']?.toString() ?? '—'),
                ('الدفع', _paymentLabel(order['payment_method']?.toString())),
                ('الحالة', _statusLabel(status)),
              ],
            ),
            if (canAdjust) ...[
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFFEAF8FD),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: Color(0xFF319AC2),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'صنف ناقص أو غير متوفر؟',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'عدّل الطلب قبل التجهيز النهائي وسيظهر التعديل للزبون.',
                              style: TextStyle(
                                color: Color(0xFF5F6B72),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _adjustOrder,
                        child: const Text('تعديل'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'محتويات الطلب (${items.length})',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...items.map((item) => _OrderItemCard(item: item)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'المجموع',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      '${total.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _StatusActions(
            status: status,
            busy: _busy,
            onChange: _changeStatus,
            onPrint: _print,
            onAdjust: canAdjust ? _adjustOrder : null,
          ),
        ),
      ),
    );
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('PlatformException(', '');

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'بانتظار التأكيد',
    'preparing' => 'قيد التحضير',
    'out_for_delivery' => 'بالتوصيل',
    'delivered' => 'تم التسليم',
    'cancelled' => 'ملغي',
    _ => status,
  };

  String _paymentLabel(String? method) => switch (method) {
    'cash' => 'كاش',
    'cliq' => 'CliQ',
    'card' => 'بطاقة',
    final value => value ?? '—',
  };
}

class _OrderItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _OrderItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final productRaw = item['products'];
    final product = productRaw is Map
        ? Map<String, dynamic>.from(productRaw)
        : <String, dynamic>{};
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
    final atomicPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name']?.toString() ?? 'منتج',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${TerminalReceipt.quantityLabel(item)} • ${TerminalReceipt.unitPriceLabel(item)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${(atomicPrice * quantity).toStringAsFixed(2)} د.أ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;

  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                    Text(
                      row.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusActions extends StatelessWidget {
  final String status;
  final bool busy;
  final ValueChanged<String> onChange;
  final VoidCallback onPrint;
  final VoidCallback? onAdjust;

  const _StatusActions({
    required this.status,
    required this.busy,
    required this.onChange,
    required this.onPrint,
    this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    String? next;
    String? nextLabel;
    if (status == 'pending') {
      next = 'preparing';
      nextLabel = 'قبول وبدء التجهيز';
    } else if (status == 'preparing') {
      next = 'out_for_delivery';
      nextLabel = 'خرج للتوصيل';
    } else if (status == 'out_for_delivery') {
      next = 'delivered';
      nextLabel = 'تم التسليم';
    }

    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'طباعة',
          onPressed: busy ? null : onPrint,
          icon: const Icon(Icons.print_rounded),
        ),
        if (onAdjust != null) ...[
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'تعديل الطلب',
            onPressed: busy ? null : onAdjust,
            icon: const Icon(Icons.edit_note_rounded),
          ),
        ],
        const SizedBox(width: 8),
        if (next != null)
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : () => onChange(next!),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(nextLabel!),
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Text(
                'لا توجد خطوة تالية',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
          ),
        if (status == 'pending' || status == 'preparing') ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'إلغاء الطلب',
            onPressed: busy ? null : () => onChange('cancelled'),
            icon: const Icon(Icons.cancel_outlined, color: Color(0xFFB91C1C)),
          ),
        ],
      ],
    );
  }
}
