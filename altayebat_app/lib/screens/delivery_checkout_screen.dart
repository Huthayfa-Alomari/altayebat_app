import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer_address.dart';
import '../services/supabase_service.dart';
import 'address_editor_screen.dart';
import 'order_tracking_screen.dart';

class DeliveryCheckoutScreen extends StatefulWidget {
  /// Items must be in the secure RPC shape:
  /// [{'product_id': '<uuid>', 'quantity': 2}, ...]
  final List<Map<String, dynamic>> items;

  /// Use this to clear the cart only AFTER an order was created successfully.
  final VoidCallback? onOrderCreated;

  const DeliveryCheckoutScreen({
    super.key,
    required this.items,
    this.onOrderCreated,
  });

  @override
  State<DeliveryCheckoutScreen> createState() => _DeliveryCheckoutScreenState();
}

class _DeliveryCheckoutScreenState extends State<DeliveryCheckoutScreen> {
  List<CustomerAddress> _addresses = const [];
  CustomerAddress? _selectedAddress;

  Map<String, dynamic>? _openState;
  Map<String, dynamic>? _quote;
  Map<String, dynamic> _paymentConfig = const {};

  String _paymentMethod = 'cash';
  String _substitutePolicy = 'call_me';
  final TextEditingController _note = TextEditingController();

  bool _loading = true;
  bool _quoting = false;
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        SupabaseService.getStoreOpenState(),
        SupabaseService.fetchAddresses(),
        SupabaseService.getStorePaymentConfig(),
      ]);

      final openState = results[0] as Map<String, dynamic>;
      final addresses = results[1] as List<CustomerAddress>;
      final paymentConfig = results[2] as Map<String, dynamic>;

      CustomerAddress? selected;
      if (addresses.isNotEmpty) {
        selected = addresses.firstWhere(
          (address) => address.isDefault,
          orElse: () => addresses.first,
        );
      }

      if (!mounted) return;
      setState(() {
        _openState = openState;
        _addresses = addresses;
        _selectedAddress = selected;
        _paymentConfig = paymentConfig;
      });

      if (selected != null) {
        await _loadQuote(selected);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadQuote(CustomerAddress address) async {
    setState(() {
      _quoting = true;
      _quote = null;
      _error = null;
    });

    try {
      final quote = await SupabaseService.checkoutQuoteV2(
        items: widget.items,
        addressId: address.id,
      );
      if (!mounted) return;
      setState(() => _quote = quote);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _selectAddress(CustomerAddress address) async {
    setState(() => _selectedAddress = address);
    await _loadQuote(address);
  }

  Future<void> _addAddress() async {
    final created = await Navigator.of(context).push<CustomerAddress>(
      MaterialPageRoute(
        builder: (_) => AddressEditorScreen(makeDefault: _addresses.isEmpty),
      ),
    );

    if (created == null || !mounted) return;

    final addresses = await SupabaseService.fetchAddresses();
    if (!mounted) return;

    setState(() {
      _addresses = addresses;
      _selectedAddress = created;
      _error = null;
    });
    await _loadQuote(created);
  }

  Future<void> _editSelectedAddress() async {
    final selected = _selectedAddress;
    if (selected == null) return;

    final updated = await Navigator.of(context).push<CustomerAddress>(
      MaterialPageRoute(builder: (_) => AddressEditorScreen(address: selected)),
    );

    if (updated == null || !mounted) return;

    final addresses = await SupabaseService.fetchAddresses();
    if (!mounted) return;

    setState(() {
      _addresses = addresses;
      _selectedAddress = updated;
    });
    await _loadQuote(updated);
  }

  Future<void> _placeOrder() async {
    final address = _selectedAddress;
    final quote = _quote;

    if (address == null) {
      setState(() => _error = 'أضف عنوان التوصيل أولًا');
      return;
    }

    if (quote == null || quote['serviceable'] != true) {
      setState(() => _error = 'لا يمكن التوصيل إلى هذا العنوان حاليًا');
      return;
    }

    if (quote['meets_min_order'] != true) {
      setState(() => _error = 'قيمة السلة أقل من الحد الأدنى للطلب');
      return;
    }

    if (_openState?['open'] != true) {
      setState(() => _error = 'المتجر لا يستقبل طلبات الآن');
      return;
    }

    setState(() {
      _placing = true;
      _error = null;
    });

    String? orderId;
    String? paymentWarning;

    try {
      orderId = await SupabaseService.createDeliveryOrder(
        items: widget.items,
        addressId: address.id,
        paymentMethod: _paymentMethod,
        customerNote: _note.text,
        substitutePolicy: _substitutePolicy,
      );

      widget.onOrderCreated?.call();

      if (_paymentMethod == 'card') {
        try {
          final paymentUrl = await SupabaseService.startCardPayment(orderId);
          final uri = Uri.parse(paymentUrl);
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened) {
            paymentWarning =
                'تم إنشاء الطلب، لكن تعذر فتح صفحة الدفع. يمكنك متابعة الطلب من شاشة التتبع.';
          }
        } catch (error) {
          paymentWarning =
              'تم إنشاء الطلب، لكن لم تبدأ عملية الدفع بالبطاقة: ${_message(error)}';
        }
      }

      if (!mounted) return;

      if (paymentWarning != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(paymentWarning)));
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: orderId!),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) => '${_number(value).toStringAsFixed(2)} د.أ';

  @override
  Widget build(BuildContext context) {
    final open = _openState?['open'] == true;
    final quote = _quote;
    final serviceable = quote?['serviceable'] == true;
    final meetsMin = quote?['meets_min_order'] == true;
    final service = quote?['service'] is Map
        ? Map<String, dynamic>.from(quote!['service'] as Map)
        : const <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(title: const Text('إتمام الطلب')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
                children: [
                  _StoreStateCard(openState: _openState),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'عنوان التوصيل',
                    trailing: TextButton.icon(
                      onPressed: _addAddress,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('عنوان جديد'),
                    ),
                    child: _addresses.isEmpty
                        ? _EmptyAddress(onAdd: _addAddress)
                        : Column(
                            children: [
                              for (final address in _addresses)
                                _AddressOption(
                                  address: address,
                                  selected: _selectedAddress?.id == address.id,
                                  onTap: () => _selectAddress(address),
                                ),
                              if (_selectedAddress != null)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton.icon(
                                    onPressed: _editSelectedAddress,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('تعديل العنوان المحدد'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'ملخص الطلب',
                    child: _quoting
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: LinearProgressIndicator(),
                          )
                        : quote == null
                        ? const Text(
                            'اختر عنوانًا حتى نحسب رسوم التوصيل والسعر النهائي.',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          )
                        : Column(
                            children: [
                              if (!serviceable)
                                const _StatusBox(
                                  success: false,
                                  text:
                                      'هذا العنوان خارج مناطق التوصيل الحالية.',
                                )
                              else ...[
                                _SummaryRow(
                                  label: 'مجموع المنتجات',
                                  value: _money(quote['subtotal']),
                                ),
                                _SummaryRow(
                                  label: 'رسوم التوصيل',
                                  value: _money(quote['delivery_fee']),
                                ),
                                const Divider(height: 22),
                                _SummaryRow(
                                  label: 'الإجمالي',
                                  value: _money(quote['total']),
                                  strong: true,
                                ),
                                if (!meetsMin) ...[
                                  const SizedBox(height: 10),
                                  _StatusBox(
                                    success: false,
                                    text:
                                        'أضف ${_money(quote['amount_to_min_order'])} للوصول للحد الأدنى.',
                                  ),
                                ],
                                if (service['eta_min_minutes'] != null ||
                                    service['eta_max_minutes'] != null) ...[
                                  const SizedBox(height: 10),
                                  _StatusBox(
                                    success: true,
                                    text:
                                        'وقت التوصيل المتوقع: ${service['eta_min_minutes'] ?? '—'}–${service['eta_max_minutes'] ?? '—'} دقيقة',
                                  ),
                                ],
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'طريقة الدفع',
                    child: Column(
                      children: [
                        _PaymentOption(
                          value: 'cash',
                          groupValue: _paymentMethod,
                          icon: Icons.payments_outlined,
                          title: 'كاش عند الاستلام',
                          subtitle: 'ادفع للسائق عند وصول الطلب',
                          onChanged: (value) =>
                              setState(() => _paymentMethod = value),
                        ),
                        _PaymentOption(
                          value: 'cliq',
                          groupValue: _paymentMethod,
                          icon: Icons.account_balance_outlined,
                          title: 'CliQ',
                          subtitle: _cliqSubtitle(),
                          onChanged: (value) =>
                              setState(() => _paymentMethod = value),
                        ),
                        _PaymentOption(
                          value: 'card',
                          groupValue: _paymentMethod,
                          icon: Icons.credit_card,
                          title: 'بطاقة بنكية',
                          subtitle: 'Visa / Mastercard عبر PayTabs',
                          onChanged: (value) =>
                              setState(() => _paymentMethod = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'خيارات إضافية',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'إذا منتج خلص من المخزون',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 7),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'call_me',
                              label: Text('اتصل بي'),
                            ),
                            ButtonSegment(
                              value: 'no_substitute',
                              label: Text('بدون بديل'),
                            ),
                          ],
                          selected: {_substitutePolicy},
                          onSelectionChanged: (selection) {
                            if (selection.isNotEmpty) {
                              setState(
                                () => _substitutePolicy = selection.first,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _note,
                          minLines: 2,
                          maxLines: 3,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة على الطلب (اختياري)',
                            hintText: 'مثال: الاتصال قبل الوصول',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _StatusBox(success: false, text: _error!),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                color: Color(0x18000000),
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: FilledButton(
            onPressed:
                _placing ||
                    _loading ||
                    _quoting ||
                    !open ||
                    !serviceable ||
                    !meetsMin
                ? null
                : _placeOrder,
            child: _placing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    quote == null
                        ? 'اختر عنوان التوصيل'
                        : 'تأكيد الطلب — ${_money(quote['total'])}',
                  ),
          ),
        ),
      ),
    );
  }

  String _cliqSubtitle() {
    final alias = _paymentConfig['cliq_alias']?.toString().trim();
    final name = _paymentConfig['cliq_recipient_name']?.toString().trim();

    if (alias == null || alias.isEmpty) {
      return 'تحويل يدوي عبر CliQ';
    }

    return [
      'Alias: $alias',
      if (name != null && name.isNotEmpty) name,
    ].join(' — ');
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                trailing ?? const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _StoreStateCard extends StatelessWidget {
  final Map<String, dynamic>? openState;

  const _StoreStateCard({required this.openState});

  @override
  Widget build(BuildContext context) {
    final open = openState?['open'] == true;
    return _StatusBox(
      success: open,
      text: open ? 'المتجر يستقبل الطلبات الآن' : 'المتجر لا يستقبل طلبات الآن',
    );
  }
}

class _EmptyAddress extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyAddress({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 40,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(height: 8),
          const Text(
            'حدد مكان التوصيل مرة واحدة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'بعدها رح نحسب الرسوم ووقت التوصيل تلقائيًا.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('إضافة عنوان'),
          ),
        ],
      ),
    );
  }
}

class _AddressOption extends StatelessWidget {
  final CustomerAddress address;
  final bool selected;
  final VoidCallback onTap;

  const _AddressOption({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1,
            ),
            color: selected
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.28)
                : Colors.white,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFF9CA3AF),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      address.compactAddress,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              if (address.hasCoordinates)
                const Icon(
                  Icons.location_on,
                  size: 20,
                  color: Color(0xFF16A34A),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final ValueChanged<String> onChanged;

  const _PaymentOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
      fontSize: strong ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  final bool success;
  final String text;

  const _StatusBox({required this.success, required this.text});

  @override
  Widget build(BuildContext context) {
    final background = success
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFFFF1F2);
    final foreground = success
        ? const Color(0xFF166534)
        : const Color(0xFF9F1239);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.info_outline,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
