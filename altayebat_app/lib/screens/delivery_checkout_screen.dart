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
  bool _cardPaymentReady = false;

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
        SupabaseService.isCardPaymentConfigured(),
      ]);

      final openState = results[0] as Map<String, dynamic>;
      final addresses = results[1] as List<CustomerAddress>;
      final paymentConfig = results[2] as Map<String, dynamic>;
      final cardPaymentReady = results[3] as bool;

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
        _cardPaymentReady = cardPaymentReady;
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

  Future<void> _showAddressPicker() async {
    if (_addresses.isEmpty) {
      await _addAddress();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر عنوان التوصيل',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _addresses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final address = _addresses[index];
                      final selected = _selectedAddress?.id == address.id;
                      return _AddressSheetOption(
                        address: address,
                        selected: selected,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await _selectAddress(address);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _addAddress();
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('إضافة عنوان جديد'),
                ),
              ],
            ),
          ),
        );
      },
    );
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

    final cliqAlias = _paymentConfig['cliq_alias']?.toString().trim() ?? '';
    if (_paymentMethod == 'cliq' && cliqAlias.isEmpty) {
      setState(() => _error = 'الدفع عبر CliQ غير مفعّل حاليًا');
      return;
    }

    if (_paymentMethod == 'card') {
      final ready = await SupabaseService.isCardPaymentConfigured();
      if (!mounted) return;
      setState(() => _cardPaymentReady = ready);

      if (!ready) {
        setState(() => _error = 'الدفع بالبطاقة غير مفعّل حاليًا');
        return;
      }
    }

    setState(() {
      _placing = true;
      _error = null;
    });

    try {
      final orderId = await SupabaseService.createDeliveryOrder(
        items: widget.items,
        addressId: address.id,
        paymentMethod: _paymentMethod,
        customerNote: _note.text,
        substitutePolicy: _substitutePolicy,
      );

      String? paymentWarning;

      if (_paymentMethod == 'card') {
        try {
          final paymentUrl = await SupabaseService.startCardPayment(orderId);
          final uri = Uri.parse(paymentUrl);
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );

          // A PayTabs transaction now exists, so the cart can be cleared even
          // if the browser did not open. The tracking screen can reconcile it.
          widget.onOrderCreated?.call();

          if (!opened) {
            paymentWarning =
                'تم إنشاء عملية الدفع، لكن تعذر فتح صفحة PayTabs. افتح الطلب واضغط تحقق من حالة الدفع.';
          }
        } catch (error) {
          // If PayTabs never created a transaction, cancel the just-created
          // order atomically and restore stock so the customer can retry.
          final cancelled = await SupabaseService.cancelUnstartedCardOrder(
            orderId,
          );

          if (!mounted) return;

          if (cancelled) {
            setState(() {
              _error =
                  'تعذر بدء الدفع بالبطاقة، لذلك أُلغي الطلب وأُعيد المخزون تلقائيًا. جرّب مرة ثانية.';
            });
            return;
          }

          // A transaction may already have been created even if the client
          // lost the response. Keep the order and let tracking reconcile it.
          widget.onOrderCreated?.call();
          paymentWarning =
              'تم إنشاء الطلب، لكن تعذر فتح الدفع: ${_message(error)}';
        }
      } else {
        widget.onOrderCreated?.call();
      }

      if (!mounted) return;

      if (paymentWarning != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(paymentWarning)));
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: orderId),
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

  bool get _hasCliqConfig {
    final alias = _paymentConfig['cliq_alias']?.toString().trim() ?? '';
    return alias.isNotEmpty;
  }

  String _cliqSubtitle() {
    final alias = _paymentConfig['cliq_alias']?.toString().trim();
    final name = _paymentConfig['cliq_recipient_name']?.toString().trim();

    if (alias == null || alias.isEmpty) {
      return 'غير مفعّل حاليًا';
    }

    return [
      'Alias: $alias',
      if (name != null && name.isNotEmpty) name,
    ].join(' — ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = _openState?['open'] == true;
    final quote = _quote;
    final serviceable = quote?['serviceable'] == true;
    final meetsMin = quote?['meets_min_order'] == true;
    final service = quote?['service'] is Map
        ? Map<String, dynamic>.from(quote!['service'] as Map)
        : const <String, dynamic>{};

    final canPlaceOrder =
        !_placing &&
        !_loading &&
        !_quoting &&
        open &&
        serviceable &&
        meetsMin;

    return Scaffold(
      appBar: AppBar(title: const Text('إتمام الطلب')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 170),
                children: [
                  if (!open) ...[
                    const _StatusBox(
                      success: false,
                      text: 'المتجر لا يستقبل طلبات الآن.',
                    ),
                    const SizedBox(height: 10),
                  ],
                  _Section(
                    step: '1',
                    title: 'عنوان التوصيل',
                    child: _selectedAddress == null
                        ? _EmptyAddress(onAdd: _addAddress)
                        : _SelectedAddressCard(
                            address: _selectedAddress!,
                            onChange: _showAddressPicker,
                            onEdit: _editSelectedAddress,
                          ),
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    step: '2',
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
                          enabled: _hasCliqConfig,
                          onChanged: (value) =>
                              setState(() => _paymentMethod = value),
                        ),
                        _PaymentOption(
                          value: 'card',
                          groupValue: _paymentMethod,
                          icon: Icons.credit_card_rounded,
                          title: 'بطاقة بنكية',
                          subtitle: _cardPaymentReady
                              ? 'Visa / Mastercard عبر PayTabs'
                              : 'غير مفعّل حاليًا',
                          enabled: _cardPaymentReady,
                          onChanged: (value) =>
                              setState(() => _paymentMethod = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _OptionalPreferences(
                    substitutePolicy: _substitutePolicy,
                    noteController: _note,
                    onSubstitutePolicyChanged: (value) {
                      setState(() => _substitutePolicy = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    step: '3',
                    title: 'ملخص الطلب',
                    child: _quoting
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: LinearProgressIndicator(),
                          )
                        : quote == null
                        ? const Text(
                            'حدد عنوان التوصيل حتى نحسب السعر النهائي.',
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
                                  label: 'المنتجات',
                                  value: _money(quote['subtotal']),
                                ),
                                _SummaryRow(
                                  label: 'التوصيل',
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
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.schedule_rounded,
                                          size: 20,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'التوصيل المتوقع: ${service['eta_min_minutes'] ?? '—'}–${service['eta_max_minutes'] ?? '—'} دقيقة',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _StatusBox(success: false, text: _error!),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 14,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canPlaceOrder ? _placeOrder : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
                            ? 'حدد عنوان التوصيل'
                            : serviceable && meetsMin
                            ? 'تأكيد الطلب • ${_money(quote['total'])}'
                            : 'راجع بيانات الطلب',
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String step;
  final String title;
  final Widget child;

  const _Section({
    required this.step,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyAddress extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyAddress({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 7),
          const Text(
            'وين نوصّل طلبك؟',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 3),
          Text(
            'أضف موقعك مرة واحدة، وبعدها نحسب التوصيل تلقائيًا.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('إضافة عنوان التوصيل'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedAddressCard extends StatelessWidget {
  final CustomerAddress address;
  final VoidCallback onChange;
  final VoidCallback onEdit;

  const _SelectedAddressCard({
    required this.address,
    required this.onChange,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (address.hasCoordinates)
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onChange,
                  child: const Text('تغيير العنوان'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'تعديل العنوان',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressSheetOption extends StatelessWidget {
  final CustomerAddress address;
  final bool selected;
  final VoidCallback onTap;

  const _AddressSheetOption({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.compactAddress,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _PaymentOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value == groupValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? () => onChanged(value) : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: enabled
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: !enabled
                    ? theme.colorScheme.outline
                    : selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionalPreferences extends StatelessWidget {
  final String substitutePolicy;
  final TextEditingController noteController;
  final ValueChanged<String> onSubstitutePolicyChanged;

  const _OptionalPreferences({
    required this.substitutePolicy,
    required this.noteController,
    required this.onSubstitutePolicyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(Icons.tune_rounded),
          title: const Text(
            'ملاحظات وخيارات إضافية',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('اختياري'),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'إذا منتج خلص من المخزون',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'call_me',
                    label: Text('اتصل بي'),
                  ),
                  ButtonSegment(
                    value: 'remove_item',
                    label: Text('احذف المنتج'),
                  ),
                ],
                selected: {substitutePolicy},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    onSubstitutePolicyChanged(selection.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'ملاحظة على الطلب',
                hintText: 'مثال: الاتصال قبل الوصول',
              ),
            ),
          ],
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
    final theme = Theme.of(context);
    final style = TextStyle(
      fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
      fontSize: strong ? 20 : 14,
      color: strong ? theme.colorScheme.primary : null,
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
