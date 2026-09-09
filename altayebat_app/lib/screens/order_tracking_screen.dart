import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import 'order_receipt_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  StreamSubscription<Map<String, dynamic>>? _orderSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _driverLocationSubscription;
  Timer? _pollTimer;
  Timer? _driverFreshnessTimer;

  Map<String, dynamic> _order = const {};
  Map<String, dynamic>? _driverLocation;
  Map<String, dynamic> _paymentConfig = const {};

  bool _loading = true;
  bool _actionBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _subscribe();
    _subscribeDriverLocation();
    _driverFreshnessTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _driverLocation != null) {
        setState(() {});
      }
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshOrder(silent: true),
    );
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _driverLocationSubscription?.cancel();
    _pollTimer?.cancel();
    _driverFreshnessTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final results = await Future.wait([
        SupabaseService.fetchOrder(widget.orderId),
        SupabaseService.getStorePaymentConfig(),
      ]);

      if (!mounted) return;
      setState(() {
        _order = results[0];
        _paymentConfig = results[1];
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _orderSubscription = SupabaseService.watchOrder(widget.orderId).listen(
      (order) {
        if (!mounted || order.isEmpty) return;
        setState(() {
          _order = order;
          _error = null;
        });
      },
      onError: (_) {
        // Polling remains active as a fallback if Realtime is unavailable.
      },
    );
  }

  void _subscribeDriverLocation() {
    _driverLocationSubscription =
        SupabaseService.watchDriverLocation(widget.orderId).listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _driverLocation = rows.isEmpty
                  ? null
                  : Map<String, dynamic>.from(rows.first);
            });
          },
          onError: (_) {
            // Order polling remains active; the live map will recover when
            // Supabase Realtime reconnects.
          },
        );
  }

  Future<void> _refreshOrder({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _actionBusy = true);
    }

    try {
      final order = await SupabaseService.fetchOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
    } catch (error) {
      if (!silent && mounted) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _reconcileCardPayment() async {
    if (_actionBusy) return;
    setState(() {
      _actionBusy = true;
      _error = null;
    });

    try {
      await SupabaseService.reconcileCardPayment(widget.orderId);
      await _refreshOrder(silent: true);
      if (!mounted) return;
      _show('تم تحديث حالة الدفع');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _retryCardPayment() async {
    if (_actionBusy) return;
    setState(() {
      _actionBusy = true;
      _error = null;
    });

    try {
      final configured = await SupabaseService.isCardPaymentConfigured();
      if (!configured) {
        throw StateError('الدفع بالبطاقة غير مفعّل حاليًا');
      }

      final paymentUrl = await SupabaseService.startCardPayment(widget.orderId);
      await _refreshOrder(silent: true);

      final opened = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw StateError('تعذر فتح صفحة PayTabs');
      }
    } catch (error) {
      final reference = _order['payment_reference']?.toString().trim() ?? '';

      if (reference.isEmpty) {
        final cancelled = await SupabaseService.cancelUnstartedCardOrder(
          widget.orderId,
        );
        if (cancelled) {
          await _refreshOrder(silent: true);
          if (!mounted) return;
          setState(() {
            _error =
                'تعذر بدء الدفع، لذلك أُلغي الطلب وأُعيد المخزون تلقائيًا.';
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _copyCliqAlias() async {
    final alias = _cliqAlias;
    if (alias.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: alias));
    if (mounted) _show('تم نسخ CliQ Alias');
  }

  Future<void> _sendCliqProof() async {
    final phone = _storePhoneDigits;
    if (phone.isEmpty) {
      _show('رقم واتساب المول غير مضاف بعد');
      return;
    }

    final shortId = _shortOrderId;
    final amount = _money(_order['total']);
    final message =
        'مرحباً، أرفق إثبات تحويل CliQ للطلب #$shortId بقيمة $amount.';

    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      _show('تعذر فتح واتساب');
    }
  }

  Future<void> _callStore() async {
    final phone = _storePhoneDigits;
    if (phone.isEmpty) {
      _show('رقم المول غير مضاف بعد');
      return;
    }

    final uri = Uri.parse('tel:+$phone');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      _show('تعذر فتح الاتصال');
    }
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  String get _shortOrderId {
    final id = widget.orderId.replaceAll('-', '');
    return id.substring(0, id.length >= 8 ? 8 : id.length).toUpperCase();
  }

  String get _paymentMethod =>
      _order['payment_method']?.toString().toLowerCase() ?? '';

  String get _paymentStatus =>
      _order['payment_status']?.toString().toLowerCase() ?? '';

  String get _orderStatus =>
      _order['status']?.toString().toLowerCase() ?? 'pending';

  String get _cliqAlias =>
      _paymentConfig['cliq_alias']?.toString().trim() ?? '';

  String get _cliqRecipient =>
      _paymentConfig['cliq_recipient_name']?.toString().trim() ?? '';

  String get _storePhoneDigits {
    final raw = _paymentConfig['phone']?.toString() ?? '';
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0') && digits.length >= 9) {
      digits = '962${digits.substring(1)}';
    }
    return digits;
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) => '${_number(value).toStringAsFixed(2)} د.أ';

  String _paymentMethodLabel() {
    switch (_paymentMethod) {
      case 'card':
        return 'Visa / Mastercard';
      case 'cliq':
        return 'CliQ';
      case 'cash':
        return 'كاش عند الاستلام';
      default:
        return '—';
    }
  }

  String _paymentStatusLabel() {
    if (_paymentMethod == 'cash' && _paymentStatus == 'unpaid') {
      return 'الدفع عند الاستلام';
    }

    switch (_paymentStatus) {
      case 'paid':
        return 'تم الدفع';
      case 'failed':
        return 'فشل الدفع';
      case 'refunded':
        return 'تم رد المبلغ';
      case 'pending':
        return 'بانتظار تأكيد الدفع';
      case 'unpaid':
        return 'غير مدفوع';
      default:
        return '—';
    }
  }

  String _orderStatusLabel() {
    switch (_orderStatus) {
      case 'pending':
        return 'بانتظار تأكيد المول';
      case 'preparing':
        return 'قيد التحضير';
      case 'out_for_delivery':
        return 'بالتوصيل إليك';
      case 'delivered':
        return 'تم التسليم';
      case 'cancelled':
        return 'تم إلغاء الطلب';
      default:
        return 'بانتظار التحديث';
    }
  }

  int get _stageIndex {
    switch (_orderStatus) {
      case 'pending':
        return 0;
      case 'preparing':
        return 1;
      case 'out_for_delivery':
        return 2;
      case 'delivered':
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final cancelled = _orderStatus == 'cancelled';
    final cardPending = _paymentMethod == 'card' && _paymentStatus == 'pending';
    final cardReference = _order['payment_reference']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('تتبع الطلب'), centerTitle: true),
      floatingActionButton: _storePhoneDigits.isEmpty
          ? null
          : FloatingActionButton.small(
              onPressed: _callStore,
              tooltip: 'اتصال بالمول',
              child: const Icon(Icons.headset_mic_outlined),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refreshOrder(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
                children: [
                  _OrderHeaderCard(
                    shortId: _shortOrderId,
                    status: _orderStatusLabel(),
                    cancelled: cancelled,
                  ),
                  const SizedBox(height: 14),
                  _PaymentCard(
                    method: _paymentMethodLabel(),
                    paymentStatus: _paymentStatusLabel(),
                    busy: _actionBusy,
                    showCardAction: cardPending,
                    cardActionLabel: cardReference.isEmpty
                        ? 'إكمال الدفع بالبطاقة'
                        : 'تحقق من حالة الدفع',
                    onCardAction: cardReference.isEmpty
                        ? _retryCardPayment
                        : _reconcileCardPayment,
                  ),
                  if (_paymentMethod == 'cliq' &&
                      _paymentStatus == 'pending') ...[
                    const SizedBox(height: 14),
                    _CliqCard(
                      alias: _cliqAlias,
                      recipient: _cliqRecipient,
                      amount: _money(_order['total']),
                      canSendProof: _storePhoneDigits.isNotEmpty,
                      onCopy: _copyCliqAlias,
                      onSendProof: _sendCliqProof,
                    ),
                  ],
                  if (_orderStatus == 'out_for_delivery') ...[
                    const SizedBox(height: 14),
                    _LiveDeliveryCard(
                      location: _driverLocation,
                      addressSnapshot: _order['address_snapshot'],
                    ),
                  ],
                  if (_order.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderReceiptScreen(orderId: widget.orderId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('عرض الإيصال'),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _MessageBox(text: _error!, error: true),
                  ],
                  const SizedBox(height: 22),
                  if (cancelled)
                    const _MessageBox(
                      text:
                          'هذا الطلب ملغي. إذا كنت ما زلت تريد المنتجات، ارجع للسلة وأنشئ طلبًا جديدًا.',
                      error: true,
                    )
                  else
                    _Timeline(currentIndex: _stageIndex, color: color),
                ],
              ),
            ),
    );
  }
}

class _OrderHeaderCard extends StatelessWidget {
  final String shortId;
  final String status;
  final bool cancelled;

  const _OrderHeaderCard({
    required this.shortId,
    required this.status,
    required this.cancelled,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            cancelled ? Icons.cancel_outlined : Icons.receipt_long_outlined,
            color: primary,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'رقم الطلب',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
                Text(
                  '#$shortId',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          Text(
            status,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: cancelled ? const Color(0xFFB91C1C) : primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final String method;
  final String paymentStatus;
  final bool busy;
  final bool showCardAction;
  final String cardActionLabel;
  final VoidCallback onCardAction;

  const _PaymentCard({
    required this.method,
    required this.paymentStatus,
    required this.busy,
    required this.showCardAction,
    required this.cardActionLabel,
    required this.onCardAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _InfoRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'طريقة الدفع',
              value: method,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: 'حالة الدفع',
              value: paymentStatus,
            ),
            if (showCardAction) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onCardAction,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(cardActionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CliqCard extends StatelessWidget {
  final String alias;
  final String recipient;
  final String amount;
  final bool canSendProof;
  final VoidCallback onCopy;
  final VoidCallback onSendProof;

  const _CliqCard({
    required this.alias,
    required this.recipient,
    required this.amount,
    required this.canSendProof,
    required this.onCopy,
    required this.onSendProof,
  });

  @override
  Widget build(BuildContext context) {
    final configured = alias.isNotEmpty;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'إكمال دفع CliQ',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'حوّل $amount ثم أرسل إثبات التحويل للمول.',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 14),
            if (!configured)
              const _MessageBox(
                text: 'CliQ Alias غير مضاف بعد. تواصل مع المول قبل التحويل.',
                error: true,
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CliQ Alias',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            alias,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          if (recipient.isNotEmpty)
                            Text(
                              recipient,
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onCopy,
                      tooltip: 'نسخ Alias',
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canSendProof ? onSendProof : null,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('إرسال إثبات الدفع عبر واتساب'),
              ),
              if (!canSendProof) ...[
                const SizedBox(height: 8),
                const Text(
                  'رقم واتساب المول غير مضاف بعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveDeliveryCard extends StatelessWidget {
  final Map<String, dynamic>? location;
  final dynamic addressSnapshot;

  const _LiveDeliveryCard({
    required this.location,
    required this.addressSnapshot,
  });

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  DateTime? _time(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _freshnessText(DateTime? updatedAt) {
    if (updatedAt == null) return 'بانتظار أول تحديث من المندوب';
    final seconds = DateTime.now().difference(updatedAt).inSeconds;
    if (seconds < 0 || seconds < 25) return 'الموقع مباشر الآن';
    if (seconds < 60) return 'آخر تحديث قبل $seconds ثانية';
    final minutes = seconds ~/ 60;
    if (minutes == 1) return 'آخر تحديث قبل دقيقة';
    if (minutes < 10) return 'آخر تحديث قبل $minutes دقائق';
    return 'الاتصال بالمندوب ضعيف — آخر تحديث قبل $minutes دقيقة';
  }

  Color _freshnessColor(DateTime? updatedAt) {
    if (updatedAt == null) return const Color(0xFF6B7280);
    final seconds = DateTime.now().difference(updatedAt).inSeconds;
    if (seconds < 45) return const Color(0xFF15803D);
    if (seconds < 180) return const Color(0xFFB45309);
    return const Color(0xFFB91C1C);
  }

  @override
  Widget build(BuildContext context) {
    final lat = _number(location?['lat']);
    final lng = _number(location?['lng']);
    final updatedAt = _time(
      location?['recorded_at'] ?? location?['updated_at'],
    );

    final snapshot = addressSnapshot is Map
        ? Map<String, dynamic>.from(addressSnapshot as Map)
        : const <String, dynamic>{};
    final destinationLat = _number(snapshot['lat']);
    final destinationLng = _number(snapshot['lng']);

    if (lat == null || lng == null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.delivery_dining_outlined,
                color: Color(0xFFE31E24),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المندوب بالطريق إليك',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'سيظهر موقع المندوب هنا تلقائيًا عند أول تحديث GPS.',
                      style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final driverPoint = LatLng(lat, lng);
    final destinationPoint = destinationLat != null && destinationLng != null
        ? LatLng(destinationLat, destinationLng)
        : null;

    double? distanceKm;
    if (destinationPoint != null) {
      distanceKm = Distance().as(
        LengthUnit.Kilometer,
        driverPoint,
        destinationPoint,
      );
    }

    final statusColor = _freshnessColor(updatedAt);
    final freshness = _freshnessText(updatedAt);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 245,
            child: FlutterMap(
              key: ValueKey(
                '${lat.toStringAsFixed(5)}:${lng.toStringAsFixed(5)}',
              ),
              options: MapOptions(
                initialCenter: driverPoint,
                initialZoom: destinationPoint == null ? 16 : 14.5,
                minZoom: 7,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.altayebat.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: driverPoint,
                      width: 62,
                      height: 62,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.delivery_dining,
                          color: Color(0xFFE31E24),
                          size: 38,
                        ),
                      ),
                    ),
                    if (destinationPoint != null)
                      Marker(
                        point: destinationPoint,
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.home_rounded,
                          color: Color(0xFF1D4ED8),
                          size: 42,
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'المندوب بالطريق إليك',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        freshness,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (distanceKm != null) ...[
                  const SizedBox(height: 9),
                  Text(
                    distanceKm < 1
                        ? 'يبعد عن موقع التوصيل تقريبًا ${(distanceKm * 1000).round()} متر'
                        : 'يبعد عن موقع التوصيل تقريبًا ${distanceKm.toStringAsFixed(1)} كم',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                const Text(
                  'المسافة تقريبية بخط مستقيم، والخريطة تتحدث تلقائيًا.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6B7280)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final int currentIndex;
  final Color color;

  const _Timeline({required this.currentIndex, required this.color});

  static const labels = [
    'بانتظار تأكيد المول',
    'قيد التحضير',
    'بالتوصيل إليك',
    'تم التسليم',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          _TimelineStep(
            label: labels[i],
            active: i <= currentIndex,
            current: i == currentIndex,
            showLine: i < labels.length - 1,
            color: color,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final bool active;
  final bool current;
  final bool showLine;
  final Color color;

  const _TimelineStep({
    required this.label,
    required this.active,
    required this.current,
    required this.showLine,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final muted = const Color(0xFFE5E7EB);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? color : muted,
                  ),
                  child: Icon(
                    current
                        ? Icons.check
                        : active
                        ? Icons.check
                        : Icons.circle,
                    size: current ? 20 : 10,
                    color: Colors.white,
                  ),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 3,
                      color: active && !current ? color : muted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 10,
                top: 6,
                bottom: 36,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: current ? FontWeight.w900 : FontWeight.w600,
                  color: active
                      ? const Color(0xFF111827)
                      : const Color(0xFF9CA3AF),
                  fontSize: current ? 16 : 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  final String text;
  final bool error;

  const _MessageBox({required this.text, required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? const Color(0xFFB91C1C) : const Color(0xFF166534),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
