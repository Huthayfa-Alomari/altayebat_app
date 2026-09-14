import 'package:flutter/material.dart';

class TerminalOrderAdjustment {
  final List<Map<String, dynamic>> lines;
  final String reason;

  const TerminalOrderAdjustment({required this.lines, required this.reason});
}

Future<TerminalOrderAdjustment?> showTerminalOrderAdjustmentSheet(
  BuildContext context,
  List<Map<String, dynamic>> items,
) {
  return showModalBottomSheet<TerminalOrderAdjustment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _AdjustmentSheet(items: items),
  );
}

class _AdjustmentSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const _AdjustmentSheet({required this.items});

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  late final Map<String, int> _quantities;
  final Set<String> _markUnavailable = <String>{};
  final _reasonController = TextEditingController(
    text: 'تعديل بسبب عدم توفر صنف أو كمية في المول',
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantities = {
      for (final item in widget.items)
        item['id'].toString(): (item['quantity'] as num?)?.toInt() ?? 0,
    };
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  int _step(Map<String, dynamic> item) {
    return item['sale_type_snapshot']?.toString() == 'piece' ? 1 : 50;
  }

  String _name(Map<String, dynamic> item) {
    final raw = item['products'];
    if (raw is Map) return raw['name']?.toString() ?? 'منتج';
    return item['product_name']?.toString() ?? 'منتج';
  }

  void _setQuantity(Map<String, dynamic> item, int value) {
    final id = item['id'].toString();
    setState(() {
      _quantities[id] = value < 0 ? 0 : value;
      if (value > 0) _markUnavailable.remove(id);
      _error = null;
    });
  }

  void _unavailable(Map<String, dynamic> item) {
    final id = item['id'].toString();
    setState(() {
      _quantities[id] = 0;
      _markUnavailable.add(id);
      _error = null;
    });
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'اكتب سبب التعديل.');
      return;
    }

    if (widget.items.every(
      (item) => (_quantities[item['id'].toString()] ?? 0) == 0,
    )) {
      setState(() => _error = 'لا يمكن حذف كل الأصناف. ألغِ الطلب بدلًا من ذلك.');
      return;
    }

    final lines = <Map<String, dynamic>>[];
    for (final item in widget.items) {
      final id = item['id'].toString();
      final original = (item['quantity'] as num?)?.toInt() ?? 0;
      final next = _quantities[id] ?? original;
      final unavailable = _markUnavailable.contains(id);
      if (next == original && !unavailable) continue;
      lines.add({
        'item_id': id,
        'quantity': next,
        'mark_unavailable': unavailable,
      });
    }

    if (lines.isEmpty) {
      setState(() => _error = 'لم يتم تغيير أي صنف.');
      return;
    }

    Navigator.of(context).pop(
      TerminalOrderAdjustment(lines: lines, reason: reason),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تعديل الطلب',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'إذا صنف غير موجود اختَر «غير متوفر». سيتحدث الطلب والإيصال ويصل إشعار للزبون.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 14),
            ...widget.items.map((item) {
              final id = item['id'].toString();
              final quantity = _quantities[id] ?? 0;
              final step = _step(item);
              final unavailable = _markUnavailable.contains(id);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _name(item),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          IconButton.outlined(
                            onPressed: () => _setQuantity(item, quantity - step),
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          Expanded(
                            child: Text(
                              '$quantity',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: () => _setQuantity(item, quantity + step),
                            icon: const Icon(Icons.add_rounded),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => _unavailable(item),
                            icon: const Icon(Icons.remove_shopping_cart_outlined),
                            label: Text(unavailable ? 'غير متوفر ✓' : 'غير متوفر'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'سبب التعديل'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ وإبلاغ الزبون'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
