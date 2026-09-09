import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/driver_tracking_service.dart';

class DriverModeScreen extends StatefulWidget {
  const DriverModeScreen({
    super.key,
    required this.token,
    required this.onClose,
  });

  final String token;
  final VoidCallback onClose;

  @override
  State<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends State<DriverModeScreen> {
  Map<String, dynamic>? _data;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;

  bool _loading = true;
  bool _working = false;
  bool _tracking = false;
  bool _pushInFlight = false;
  String? _error;
  DateTime? _lastPushAt;

  String get _status => (_data?['order_status'] ?? '').toString();

  bool get _orderClosed =>
      _status == 'delivered' || _status == 'cancelled';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await DriverTrackingService.bootstrap(widget.token);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'تعذر فتح مهمة التوصيل. الرابط منتهي أو غير صالح.';
      });
    }
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _error = 'خدمة الموقع GPS مغلقة على الهاتف.';
      });
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        _error = 'يجب السماح للتطبيق باستخدام الموقع أثناء التوصيل.';
      });
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _error =
            'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق وفعّل الموقع.';
      });
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) {
        setState(() {
          _lastPosition = position;
          _error = null;
        });
      }
      return position;
    } on TimeoutException {
      setState(() {
        _error =
            'لم يتمكن الهاتف من تحديد الموقع خلال 20 ثانية. جرّب قرب نافذة أو خارج المبنى.';
      });
      return null;
    } catch (e) {
      setState(() {
        _error = 'تعذر قراءة GPS من الهاتف.';
      });
      return null;
    }
  }

  Future<void> _testGps() async {
    if (_working) return;
    setState(() => _working = true);
    await _getCurrentPosition();
    if (mounted) setState(() => _working = false);
  }

  Future<void> _startDelivery() async {
    if (_working || _orderClosed) return;

    setState(() {
      _working = true;
      _error = null;
    });

    final position = await _getCurrentPosition();
    if (position == null) {
      if (mounted) setState(() => _working = false);
      return;
    }

    try {
      await DriverTrackingService.startDelivery(widget.token, position);
      await _bootstrap();
      await _startTracking();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = _friendlyRpcError(e);
      });
      return;
    }

    if (mounted) setState(() => _working = false);
  }

  Future<void> _startTracking() async {
    if (_tracking || _orderClosed) return;

    final position = _lastPosition ?? await _getCurrentPosition();
    if (position == null) return;

    await _positionSub?.cancel();

    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: Duration(seconds: 5),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'أسواق الطيبات - التوصيل',
          notificationText:
              'يتم تحديث موقعك للزبون أثناء مهمة التوصيل.',
          notificationChannelName: 'تتبع التوصيل',
          enableWakeLock: true,
          enableWifiLock: true,
          setOngoing: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

    setState(() {
      _tracking = true;
      _error = null;
    });

    await _pushPosition(position);

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastPosition = position;
        if (mounted) setState(() {});
        _pushPosition(position);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _tracking = false;
          _error = 'توقف تحديث GPS. اضغط تشغيل التتبع وحاول مرة أخرى.';
        });
      },
      cancelOnError: false,
    );
  }

  Future<void> _pushPosition(Position position) async {
    if (_pushInFlight || _orderClosed) return;

    // Avoid duplicate network pushes when the device emits multiple fixes
    // nearly at the same instant.
    final now = DateTime.now();
    if (_lastPushAt != null &&
        now.difference(_lastPushAt!) < const Duration(seconds: 2)) {
      return;
    }

    _pushInFlight = true;
    try {
      await DriverTrackingService.pushLocation(widget.token, position);
      _lastPushAt = now;
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyRpcError(e);
        });
      }
    } finally {
      _pushInFlight = false;
    }
  }

  Future<void> _stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    if (mounted) setState(() => _tracking = false);
  }

  Future<void> _completeDelivery() async {
    if (_working || _status != 'out_for_delivery') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد التسليم'),
        content: const Text('هل تم تسليم الطلب للزبون؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تم التسليم'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await DriverTrackingService.completeDelivery(widget.token);
      await _stopTracking();
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyRpcError(e);
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _callCustomer() async {
    final customer = _map(_data?['customer']);
    final phone = (customer['phone'] ?? '').toString().trim();
    if (phone.isEmpty) {
      setState(() {
        _error = 'رقم الزبون غير مسجل لهذا الطلب.';
      });
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() {
        _error = 'تعذر فتح تطبيق الاتصال.';
      });
    }
  }

  Future<void> _openNavigation() async {
    final address = _map(_data?['address']);
    final lat = _findNumber(address, const [
      'lat',
      'latitude',
      'delivery_lat',
    ]);
    final lng = _findNumber(address, const [
      'lng',
      'lon',
      'longitude',
      'delivery_lng',
    ]);

    Uri uri;
    if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
      uri = Uri.https(
        'www.google.com',
        '/maps/dir/',
        {
          'api': '1',
          'destination': '$lat,$lng',
        },
      );
    } else {
      final text = _addressText(address);
      if (text.isEmpty) {
        setState(() {
          _error = 'لا توجد إحداثيات أو عنوان صالح للملاحة.';
        });
        return;
      }
      uri = Uri.https(
        'www.google.com',
        '/maps/search/',
        {
          'api': '1',
          'query': text,
        },
      );
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() {
        _error = 'تعذر فتح تطبيق الملاحة.';
      });
    }
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('مهمة التوصيل'),
            leading: IconButton(
              onPressed: () async {
                await _stopTracking();
                widget.onClose();
              },
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _data == null
                    ? _buildFatalError()
                    : _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildFatalError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 56),
            const SizedBox(height: 16),
            Text(
              _error ?? 'تعذر فتح المهمة.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _bootstrap,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final customer = _map(_data?['customer']);
    final driver = _map(_data?['driver']);
    final address = _map(_data?['address']);
    final total = _data?['total'];
    final paymentMethod = (_data?['payment_method'] ?? '').toString();
    final paymentStatus = (_data?['payment_status'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: _bootstrap,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          _infoCard(
            title: 'الزبون',
            icon: Icons.person_outline,
            rows: [
              ('الاسم', _display(customer['name'])),
              ('الهاتف', _display(customer['phone'])),
              ('العنوان', _addressText(address).isEmpty
                  ? 'غير مسجل'
                  : _addressText(address)),
            ],
          ),
          const SizedBox(height: 12),
          _infoCard(
            title: 'الطلب',
            icon: Icons.receipt_long_outlined,
            rows: [
              ('رقم الطلب', _shortId((_data?['order_id'] ?? '').toString())),
              ('المبلغ', total == null ? '—' : '$total د.أ'),
              ('الدفع', _paymentLabel(paymentMethod)),
              ('حالة الدفع', _paymentStatusLabel(paymentStatus)),
              ('المندوب', _display(driver['name'])),
            ],
          ),
          const SizedBox(height: 12),
          _gpsCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_status == 'preparing')
            FilledButton.icon(
              onPressed: _working ? null : _startDelivery,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('بدء التوصيل وتشغيل GPS'),
            )
          else if (_status == 'out_for_delivery' && !_tracking)
            FilledButton.icon(
              onPressed: _working ? null : _startTracking,
              icon: const Icon(Icons.my_location),
              label: const Text('تشغيل تتبع GPS'),
            ),
          if (_status == 'out_for_delivery') ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _working ? null : _completeDelivery,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('تم التسليم'),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _callCustomer,
            icon: const Icon(Icons.phone_outlined),
            label: const Text('اتصال بالزبون'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openNavigation,
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('فتح الملاحة'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _working ? null : _testGps,
            icon: const Icon(Icons.gps_fixed),
            label: const Text('اختبار GPS على هذا الهاتف'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _openLocationSettings,
                    child: const Text('إعدادات الموقع'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _openAppSettings,
                    child: const Text('صلاحيات التطبيق'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final bool active = _status == 'out_for_delivery';
    final bool delivered = _status == 'delivered';

    final text = switch (_status) {
      'pending' => 'الطلب بانتظار التجهيز',
      'preparing' => 'جاهز لبدء التوصيل',
      'out_for_delivery' => 'الطلب في الطريق',
      'delivered' => 'تم تسليم الطلب',
      'cancelled' => 'الطلب ملغي',
      _ => _status.isEmpty ? 'حالة غير معروفة' : _status,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              delivered
                  ? Icons.check_circle
                  : active
                      ? Icons.location_on
                      : Icons.local_shipping_outlined,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active
                        ? (_tracking
                            ? 'GPS يعمل ويتم إرسال موقعك للزبون'
                            : 'GPS غير نشط')
                        : delivered
                            ? 'تم إيقاف التتبع'
                            : 'ابدأ التوصيل عندما تستلم الطلب',
                  ),
                ],
              ),
            ),
            if (_tracking)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard() {
    final p = _lastPosition;
    final lastPush = _lastPushAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GPS',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              p == null
                  ? 'لم يتم تحديد موقع الهاتف بعد.'
                  : 'الدقة: ${p.accuracy.toStringAsFixed(0)} متر',
            ),
            if (p != null) ...[
              const SizedBox(height: 4),
              Text(
                '${p.latitude.toStringAsFixed(6)}, '
                '${p.longitude.toStringAsFixed(6)}',
                textDirection: TextDirection.ltr,
              ),
            ],
            if (lastPush != null) ...[
              const SizedBox(height: 4),
              Text('آخر إرسال: ${_time(lastPush)}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required IconData icon,
    required List<(String, String)> rows,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(height: 24),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(child: Text(row.$2)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _friendlyRpcError(Object error) {
    final text = error.toString();
    if (text.contains('INVALID_OR_EXPIRED_TRACKING_TOKEN')) {
      return 'رابط المندوب منتهي أو تم إلغاؤه.';
    }
    if (text.contains('ORDER_NOT_READY')) {
      return 'الطلب غير جاهز للتوصيل بعد.';
    }
    if (text.contains('PAYMENT_NOT_CONFIRMED')) {
      return 'الدفع الإلكتروني غير مؤكد بعد.';
    }
    if (text.contains('ORDER_CLOSED')) {
      return 'الطلب مغلق ولا يمكن تحديث موقعه.';
    }
    if (text.contains('ORDER_NOT_OUT_FOR_DELIVERY')) {
      return 'يجب أن يكون الطلب في حالة خرج للتوصيل.';
    }
    return 'حدث خطأ أثناء تحديث مهمة التوصيل. حاول مرة أخرى.';
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static double? _findNumber(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }

    for (final value in map.values) {
      if (value is Map) {
        final nested = _findNumber(
          Map<String, dynamic>.from(value),
          keys,
        );
        if (nested != null) return nested;
      }
    }

    return null;
  }

  static String _addressText(Map<String, dynamic> address) {
    const preferredKeys = [
      'full_address',
      'address',
      'address_line',
      'formatted_address',
      'label',
      'text',
      'description',
    ];

    for (final key in preferredKeys) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    final parts = <String>[];
    for (final key in const [
      'city',
      'area',
      'neighborhood',
      'street',
      'building',
      'floor',
      'notes',
    ]) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) {
        parts.add(value.trim());
      }
    }

    return parts.join('، ');
  }

  static String _display(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? 'غير مسجل' : text;
  }

  static String _shortId(String id) {
    if (id.length <= 8) return id.toUpperCase();
    return id.substring(0, 8).toUpperCase();
  }

  static String _paymentLabel(String method) {
    return switch (method) {
      'cash' => 'كاش',
      'cliq' => 'CliQ',
      'card' => 'بطاقة',
      _ => method.isEmpty ? '—' : method,
    };
  }

  static String _paymentStatusLabel(String status) {
    return switch (status) {
      'paid' => 'مدفوع',
      'unpaid' => 'غير مدفوع',
      'pending' => 'قيد التحقق',
      'failed' => 'فشل الدفع',
      _ => status.isEmpty ? '—' : status,
    };
  }

  static String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
