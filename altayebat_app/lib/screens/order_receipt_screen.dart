import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderReceiptScreen extends StatefulWidget {
  final String orderId;

  const OrderReceiptScreen({super.key, required this.orderId});

  @override
  State<OrderReceiptScreen> createState() => _OrderReceiptScreenState();
}

class _OrderReceiptScreenState extends State<OrderReceiptScreen> {
  Map<String, dynamic>? _invoice;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Supabase.instance.client.rpc(
        'get_order_invoice',
        params: {'p_order_id': widget.orderId},
      );

      if (!mounted) return;
      setState(() {
        _invoice = Map<String, dynamic>.from(data as Map);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error
            .toString()
            .replaceFirst('PostgrestException(message: ', '')
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) => '${_number(value).toStringAsFixed(2)} د.أ';

  String _paymentLabel(String value) {
    switch (value) {
      case 'cash':
        return 'كاش عند الاستلام';
      case 'cliq':
        return 'CliQ';
      case 'card':
        return 'بطاقة';
      default:
        return value.isEmpty ? '—' : value;
    }
  }

  String _addressText(Map<String, dynamic> invoice) {
    final raw = invoice['address'];
    if (raw is! Map) return '—';

    final address = Map<String, dynamic>.from(raw);
    final exact = address['address_text']?.toString().trim() ?? '';
    if (exact.isNotEmpty) return exact;

    return [
      address['city'],
      address['area'],
      address['street'],
      address['building'],
      address['floor'],
    ].where((value) => value?.toString().trim().isNotEmpty == true).join('، ');
  }

  Future<void> _openOfficialInvoice(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الفاتورة الرسمية')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إيصال الطلب'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
              ),
            )
          : _ReceiptBody(
              invoice: _invoice ?? const {},
              money: _money,
              paymentLabel: _paymentLabel,
              addressText: _addressText(_invoice ?? const {}),
              onOpenOfficialInvoice: _openOfficialInvoice,
            ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final String Function(dynamic) money;
  final String Function(String) paymentLabel;
  final String addressText;
  final Future<void> Function(String) onOpenOfficialInvoice;

  const _ReceiptBody({
    required this.invoice,
    required this.money,
    required this.paymentLabel,
    required this.addressText,
    required this.onOpenOfficialInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final official = invoice['official'] == true;
    final status = invoice['status']?.toString() ?? 'draft';
    final itemsRaw = invoice['items'];
    final items = itemsRaw is List
        ? itemsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    final externalUrl =
        invoice['external_invoice_url']?.toString().trim() ?? '';
    final documentNumber =
        (invoice['external_invoice_id']?.toString().trim().isNotEmpty == true)
        ? invoice['external_invoice_id'].toString()
        : invoice['document_number']?.toString() ?? '—';

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    invoice['store_name']?.toString() ?? 'أسواق الطيبات',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    official ? 'فاتورة رسمية مرتبطة' : 'إيصال طلب إلكتروني',
                    style: TextStyle(
                      color: official
                          ? const Color(0xFF15803D)
                          : const Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    documentNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status == 'draft' ? 'مسودة حتى يتم التسليم' : 'مستند نهائي',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!official) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'هذا إيصال طلب إلكتروني غير ضريبي. الفاتورة الرسمية تعتمد نظام المول، وعند ربط Bonanza ستظهر هنا تلقائيًا.',
                style: TextStyle(color: Color(0xFF9A3412), height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoLine(
                    label: 'الزبون',
                    value: invoice['customer_name']?.toString() ?? '—',
                  ),
                  const Divider(height: 24),
                  _InfoLine(
                    label: 'التوصيل إلى',
                    value: addressText.isEmpty ? '—' : addressText,
                  ),
                  const Divider(height: 24),
                  _InfoLine(
                    label: 'طريقة الدفع',
                    value: paymentLabel(
                      invoice['payment_method']?.toString() ?? '',
                    ),
                  ),
                  const Divider(height: 24),
                  _InfoLine(
                    label: 'حالة الدفع',
                    value: invoice['payment_status']?.toString() ?? '—',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _ItemRow(item: items[index], money: money),
                    if (index != items.length - 1) const Divider(height: 20),
                  ],
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('لا توجد أصناف في الإيصال'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TotalLine(
                    label: 'المجموع الفرعي',
                    value: money(invoice['subtotal']),
                  ),
                  const SizedBox(height: 10),
                  _TotalLine(
                    label: 'التوصيل',
                    value: money(invoice['delivery_fee']),
                  ),
                  if ((double.tryParse(invoice['discount']?.toString() ?? '') ??
                          0) !=
                      0) ...[
                    const SizedBox(height: 10),
                    _TotalLine(
                      label: 'الخصم',
                      value: '- ${money(invoice['discount'])}',
                    ),
                  ],
                  if (invoice['tax'] != null) ...[
                    const SizedBox(height: 10),
                    _TotalLine(label: 'الضريبة', value: money(invoice['tax'])),
                  ],
                  const Divider(height: 28),
                  _TotalLine(
                    label: 'الإجمالي',
                    value: money(invoice['total']),
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
          if (official && externalUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onOpenOfficialInvoice(externalUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح الفاتورة الرسمية'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(dynamic) money;

  const _ItemRow({required this.item, required this.money});

  @override
  Widget build(BuildContext context) {
    final quantity = item['quantity']?.toString() ?? '0';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['name']?.toString() ?? 'منتج',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '$quantity × ${money(item['unit_price'])}',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          money(item['subtotal']),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TotalLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _TotalLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: strong ? null : const Color(0xFF6B7280),
              fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            fontSize: strong ? 18 : 14,
          ),
        ),
      ],
    );
  }
}
