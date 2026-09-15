import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/rider_location_service.dart';
import '../services/rider_service.dart';
import '../theme/app_theme.dart';

class RiderModeScreen extends StatefulWidget {
  const RiderModeScreen({super.key, this.initialOrderId});

  final String? initialOrderId;

  @override
  State<RiderModeScreen> createState() => _RiderModeScreenState();
}

class _RiderModeScreenState extends State<RiderModeScreen>
    with WidgetsBindingObserver {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _plateController = TextEditingController();

  Map<String, dynamic>? _rider;
  List<Map<String, dynamic>> _tasks = const [];
  Timer? _heartbeatTimer;
  Timer? _refreshTimer;

  bool _loading = true;
  bool _working = false;
  bool _otpSent = false;
  String? _verifiedPhone;
  String? _error;

  bool get _approved =>
      _rider?['approval_status']?.toString() == 'approved' &&
      _rider?['is_active'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RiderLocationService.instance.lastError.addListener(_onTrackingChanged);
    RiderLocationService.instance.tracking.addListener(_onTrackingChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RiderLocationService.instance.lastError.removeListener(_onTrackingChanged);
    RiderLocationService.instance.tracking.removeListener(_onTrackingChanged);
    _heartbeatTimer?.cancel();
    _refreshTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _vehicleController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _approved) {
      unawaited(_refreshAll(showLoader: false));
    }
  }

  void _onTrackingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    _stopTimers();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      if (!RiderService.hasPhoneSession) {
        if (!mounted) return;
        setState(() {
          _rider = null;
          _tasks = const [];
          _loading = false;
        });
        return;
      }

      final rider = await RiderService.me();
      if (!mounted) return;
      setState(() {
        _rider = rider;
        _loading = false;
        if (rider != null) {
          _nameController.text = rider['name']?.toString() ?? '';
          _vehicleController.text = rider['vehicle_type']?.toString() ?? '';
          _plateController.text = rider['vehicle_plate']?.toString() ?? '';
        }
      });

      if (rider != null) {
        _startRefreshTimer();
        if (_approved) {
          await _refreshAll(showLoader: false);
          _startHeartbeat();
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = RiderService.friendlyError(error);
      });
    }
  }

  void _stopTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_heartbeat());
    });
    unawaited(_heartbeat());
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshAll(showLoader: false));
    });
  }

  Future<void> _heartbeat() async {
    if (!_approved) return;
    try {
      final status = await RiderService.heartbeat();
      if (!mounted) return;
      setState(() {
        if (_rider != null) {
          _rider = {
            ..._rider!,
            'last_seen_at': status['last_seen_at'],
            'availability_status': status['availability_status'],
            'active_orders': status['active_orders'],
            'effective_status':
                (status['active_orders'] as num? ?? 0).toInt() > 0
                ? 'busy'
                : status['availability_status'],
          };
        }
      });
    } catch (_) {
      // Presence is retried on the next heartbeat and must not interrupt a task.
    }
  }

  Future<void> _refreshAll({bool showLoader = false}) async {
    if (!RiderService.hasPhoneSession) return;
    if (showLoader && mounted) setState(() => _working = true);

    try {
      final rider = await RiderService.me();
      if (rider == null) {
        if (!mounted) return;
        setState(() {
          _rider = null;
          _tasks = const [];
        });
        return;
      }

      List<Map<String, dynamic>> tasks = const [];
      if (rider['approval_status']?.toString() == 'approved' &&
          rider['is_active'] == true) {
        tasks = await RiderService.deliveryTasks();
        final focusId = widget.initialOrderId?.trim();
        if (focusId != null && focusId.isNotEmpty) {
          tasks = [...tasks]
            ..sort((a, b) {
              final aFocus = a['id']?.toString() == focusId ? 0 : 1;
              final bFocus = b['id']?.toString() == focusId ? 0 : 1;
              if (aFocus != bFocus) return aFocus.compareTo(bFocus);
              final aOut = a['status']?.toString() == 'out_for_delivery' ? 0 : 1;
              final bOut = b['status']?.toString() == 'out_for_delivery' ? 0 : 1;
              return aOut.compareTo(bOut);
            });
        }
      }

      if (!mounted) return;
      setState(() {
        _rider = rider;
        _tasks = tasks;
        _error = null;
      });

      final activeTrackingOrders = tasks
          .where((task) => task['status']?.toString() == 'out_for_delivery')
          .map((task) => task['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      if (activeTrackingOrders.isEmpty) {
        await RiderLocationService.instance.stop();
      } else if (RiderLocationService.instance.tracking.value) {
        await RiderLocationService.instance.updateOrders(activeTrackingOrders);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (showLoader && mounted) setState(() => _working = false);
    }
  }

  Future<void> _sendOtp() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final phone = await RiderService.requestOtp(_phoneController.text);
      if (!mounted) return;
      setState(() {
        _verifiedPhone = phone;
        _otpSent = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_working || _verifiedPhone == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await RiderService.verifyOtp(
        phone: _verifiedPhone!,
        code: _otpController.text,
      );
      if (!mounted) return;
      setState(() {
        _otpSent = false;
        _otpController.clear();
      });
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _register() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final rider = await RiderService.register(
        name: _nameController.text,
        vehicleType: _vehicleController.text,
        vehiclePlate: _plateController.text,
      );
      if (!mounted) return;
      setState(() => _rider = rider);
      _startRefreshTimer();
      await _refreshAll(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setAvailability(String status) async {
    if (_working || !_approved) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await RiderService.setAvailability(status);
      await _refreshAll(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _runAction(Map<String, dynamic> task, String action) async {
    if (_working) return;
    final orderId = task['id']?.toString() ?? '';
    if (orderId.isEmpty) return;

    if (action == 'complete') {
      final cashDue = _money(task['cash_due']);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد تسليم الطلب'),
          content: Text(
            cashDue > 0
                ? 'تأكد أنك استلمت ${cashDue.toStringAsFixed(2)} د.أ نقدًا من الزبون قبل إنهاء الطلب.'
                : 'هل تم تسليم الطلب للزبون بالكامل؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(cashDue > 0 ? 'استلمت الكاش وتم التسليم' : 'تم التسليم'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    if (action == 'start') {
      final position = await RiderLocationService.instance.currentPosition();
      if (position == null) {
        if (!mounted) return;
        setState(() {
          _error = RiderLocationService.instance.lastError.value ??
              'يجب تشغيل GPS قبل بدء التوصيل.';
        });
        return;
      }
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await RiderService.deliveryAction(orderId: orderId, action: action);
      await _refreshAll(showLoader: false);

      if (action == 'start') {
        final activeIds = _tasks
            .where((item) => item['status']?.toString() == 'out_for_delivery')
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(growable: false);
        await RiderLocationService.instance.start(activeIds);
      }
      if (action == 'complete') {
        final activeIds = _tasks
            .where((item) => item['status']?.toString() == 'out_for_delivery')
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(growable: false);
        await RiderLocationService.instance.updateOrders(activeIds);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startTracking() async {
    final ids = _tasks
        .where((task) => task['status']?.toString() == 'out_for_delivery')
        .map((task) => task['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await RiderLocationService.instance.start(ids);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = RiderLocationService.instance.lastError.value ??
            'تعذر تشغيل تتبع GPS.';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _call(String? phone) async {
    final clean = phone?.trim() ?? '';
    if (clean.isEmpty) {
      setState(() => _error = 'رقم الزبون غير متوفر.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: clean);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _error = 'تعذر فتح تطبيق الاتصال.');
    }
  }

  Future<void> _navigate(Map<String, dynamic> task) async {
    final address = _asMap(task['address_snapshot']);
    final lat = _number(address['lat'] ?? address['latitude']);
    final lng = _number(
      address['lng'] ?? address['longitude'] ?? address['lon'],
    );

    final Uri uri;
    if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
      uri = Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '$lat,$lng',
      });
    } else {
      final text = _addressText(address);
      if (text.isEmpty) {
        setState(() => _error = 'لا يوجد عنوان صالح للملاحة.');
        return;
      }
      uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': text,
      });
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _error = 'تعذر فتح تطبيق الخرائط.');
    }
  }

  Future<void> _changePhone() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await RiderLocationService.instance.stop();
      await RiderService.signOut();
      await _bootstrap();
      if (!mounted) return;
      setState(() {
        _phoneController.clear();
        _otpController.clear();
        _verifiedPhone = null;
        _otpSent = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = RiderService.friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('وضع المندوب'),
          actions: [
            if (_rider != null)
              IconButton(
                tooltip: 'تحديث',
                onPressed: _working
                    ? null
                    : () => _refreshAll(showLoader: true),
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _refreshAll(showLoader: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      _introCard(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _errorCard(_error!),
                      ],
                      const SizedBox(height: 14),
                      if (!RiderService.hasPhoneSession)
                        _loginCard()
                      else if (_rider == null)
                        _registrationCard()
                      else if (_rider?['approval_status'] == 'pending')
                        _pendingCard()
                      else if (_rider?['approval_status'] == 'rejected')
                        _rejectedCard()
                      else if (_rider?['is_active'] != true)
                        _suspendedCard()
                      else
                        _dashboard(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFFEF5F68)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white24,
            child: Icon(Icons.delivery_dining_rounded, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'توصيل الطيبات',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'طلباتك، حالة العمل، GPS والتحصيل من نفس التطبيق.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard() {
    return _panel(
      title: 'دخول المندوب',
      icon: Icons.phone_android_rounded,
      child: Column(
        children: [
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_otpSent && !_working,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              hintText: '0791234567',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_otpSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'رمز التحقق',
                helperText: 'أرسلنا الرمز إلى $_verifiedPhone',
                prefixIcon: const Icon(Icons.sms_outlined),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _working ? null : (_otpSent ? _verifyOtp : _sendOtp),
              icon: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_otpSent ? Icons.verified_user_outlined : Icons.sms_outlined),
              label: Text(_otpSent ? 'تأكيد الرمز' : 'إرسال رمز الدخول'),
            ),
          ),
          if (_otpSent)
            TextButton(
              onPressed: _working
                  ? null
                  : () => setState(() {
                      _otpSent = false;
                      _otpController.clear();
                    }),
              child: const Text('تعديل رقم الهاتف'),
            ),
        ],
      ),
    );
  }

  Widget _registrationCard() {
    return _panel(
      title: 'تفعيل حساب المندوب',
      icon: Icons.badge_outlined,
      child: Column(
        children: [
          const Text(
            'رقم الهاتف تم التحقق منه. أكمل البيانات وسيظهر الطلب للإدارة للموافقة.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'اسم المندوب',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _vehicleController,
            decoration: const InputDecoration(
              labelText: 'نوع المركبة (اختياري)',
              hintText: 'سيارة / دراجة',
              prefixIcon: Icon(Icons.two_wheeler_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _plateController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'رقم المركبة (اختياري)',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _working ? null : _register,
              child: const Text('إرسال طلب التفعيل'),
            ),
          ),
          TextButton(
            onPressed: _working ? null : _changePhone,
            child: const Text('استخدام رقم هاتف آخر'),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    return _statusPanel(
      icon: Icons.hourglass_top_rounded,
      title: 'الحساب بانتظار الموافقة',
      message:
          'تم استلام تسجيلك. ستتحول البوابة تلقائيًا لوضع التوصيل بعد اعتمادك من الإدارة.',
      action: FilledButton.icon(
        onPressed: _working ? null : () => _refreshAll(showLoader: true),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('فحص حالة الموافقة'),
      ),
    );
  }

  Widget _rejectedCard() {
    return _statusPanel(
      icon: Icons.block_rounded,
      title: 'طلب المندوب غير معتمد',
      message: 'راجع إدارة أسواق الطيبات إذا كنت تعتقد أن هذا غير صحيح.',
      action: TextButton(
        onPressed: _working ? null : _changePhone,
        child: const Text('استخدام حساب آخر'),
      ),
    );
  }

  Widget _suspendedCard() {
    return _statusPanel(
      icon: Icons.pause_circle_outline_rounded,
      title: 'حساب المندوب موقوف مؤقتًا',
      message: 'الحساب معتمد لكن غير مفعّل حاليًا من الإدارة.',
      action: FilledButton.icon(
        onPressed: _working ? null : () => _refreshAll(showLoader: true),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('تحديث الحالة'),
      ),
    );
  }

  Widget _dashboard() {
    final effective = _rider?['effective_status']?.toString() ?? 'offline';
    final availability =
        _rider?['availability_status']?.toString() ?? 'offline';
    final tracking = RiderLocationService.instance.tracking.value;
    final trackingError = RiderLocationService.instance.lastError.value;
    final activeDelivery = _tasks.any(
      (task) => task['status']?.toString() == 'out_for_delivery',
    );

    return Column(
      children: [
        _panel(
          title: _rider?['name']?.toString() ?? 'المندوب',
          icon: Icons.delivery_dining_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _statusChip(effective)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniInfo(
                      'طلبات نشطة',
                      '${_tasks.length}',
                      Icons.inventory_2_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'حالة العمل',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _availabilityButton(
                      value: 'available',
                      current: availability,
                      label: 'متاح',
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _availabilityButton(
                      value: 'break',
                      current: availability,
                      label: 'استراحة',
                      icon: Icons.coffee_outlined,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _availabilityButton(
                      value: 'offline',
                      current: availability,
                      label: 'غير متاح',
                      icon: Icons.power_settings_new_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (activeDelivery) ...[
          const SizedBox(height: 12),
          _panel(
            title: 'تتبع GPS',
            icon: tracking ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tracking
                      ? 'التتبع يعمل ويحدّث موقعك للزبون أثناء التوصيل.'
                      : 'يوجد طلب خرج للتوصيل. شغّل GPS لإرسال موقعك للزبون.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (trackingError != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    trackingError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (!tracking) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _working ? null : _startTracking,
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('تشغيل تتبع الموقع'),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'طلبات التوصيل',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${_tasks.length}',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_tasks.isEmpty)
          _emptyTasks()
        else
          ..._tasks.map(_taskCard),
      ],
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final id = task['id']?.toString() ?? '';
    final status = task['status']?.toString() ?? '';
    final paymentMethod = task['payment_method']?.toString() ?? '';
    final paymentStatus = task['payment_status']?.toString() ?? '';
    final cashDue = _money(task['cash_due']);
    final pickedUp = task['rider_picked_up_at'] != null;
    final address = _asMap(task['address_snapshot']);
    final focused = widget.initialOrderId?.trim() == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: focused ? AppColors.primary : AppColors.border,
          width: focused ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: status == 'out_for_delivery'
                      ? AppColors.skySoft
                      : const Color(0xFFFFF3E5),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  status == 'out_for_delivery' ? 'بالطريق' : 'جاهز للاستلام',
                  style: TextStyle(
                    color: status == 'out_for_delivery'
                        ? AppColors.skyBlueDark
                        : const Color(0xFF9B5B00),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '#${_shortId(id)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _taskRow(Icons.person_outline, task['customer_name']?.toString() ?? 'الزبون'),
          const SizedBox(height: 7),
          _taskRow(
            Icons.location_on_outlined,
            _addressText(address).isEmpty ? 'العنوان غير مكتمل' : _addressText(address),
          ),
          const SizedBox(height: 7),
          _taskRow(
            Icons.payments_outlined,
            cashDue > 0
                ? 'تحصيل نقدي: ${cashDue.toStringAsFixed(2)} د.أ'
                : '${_paymentLabel(paymentMethod)} — ${_paymentStatusLabel(paymentStatus)}',
            emphasize: cashDue > 0,
          ),
          const SizedBox(height: 7),
          _taskRow(
            Icons.receipt_long_outlined,
            'قيمة الطلب: ${_money(task['total']).toStringAsFixed(2)} د.أ',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _call(task['customer_phone']?.toString()),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('اتصال'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _navigate(task),
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: const Text('الموقع'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!pickedUp)
            FilledButton.icon(
              onPressed: _working ? null : () => _runAction(task, 'pickup'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('استلمت الطلب من المول'),
            ),
          if (status == 'preparing') ...[
            if (!pickedUp) const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _working ? null : () => _runAction(task, 'start'),
              icon: const Icon(Icons.delivery_dining_rounded),
              label: const Text('ابدأ التوصيل'),
            ),
          ],
          if (status == 'out_for_delivery') ...[
            if (!pickedUp) const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _working ? null : () => _runAction(task, 'complete'),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(cashDue > 0 ? 'تأكيد التحصيل والتسليم' : 'تم التسليم'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyTasks() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: AppColors.textSecondary),
          SizedBox(height: 10),
          Text(
            'لا توجد طلبات مسندة إليك الآن',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 4),
          Text(
            'اترك حالتك «متاح» وسيظهر الطلب هنا فور إسناده.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _availabilityButton({
    required String value,
    required String current,
    required String label,
    required IconData icon,
  }) {
    final selected = current == value;
    return OutlinedButton(
      onPressed: _working ? null : () => _setAvailability(value),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.skySoft : Colors.white,
        side: BorderSide(
          color: selected ? AppColors.skyBlueDark : AppColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, style: const TextStyle(fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, icon) = switch (status) {
      'available' => ('متاح الآن', Icons.check_circle_rounded),
      'busy' => ('مشغول بطلب', Icons.delivery_dining_rounded),
      'break' => ('استراحة', Icons.coffee_rounded),
      _ => ('غير متاح', Icons.offline_bolt_outlined),
    };
    return _miniInfo('الحالة', label, icon);
  }

  Widget _miniInfo(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9.5,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _statusPanel({
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    return _panel(
      title: title,
      icon: icon,
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(IconData icon, String value, {bool emphasize = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static double _money(dynamic value) => _number(value) ?? 0;

  static String _shortId(String value) {
    final clean = value.replaceAll('-', '').toUpperCase();
    return clean.length <= 8 ? clean : clean.substring(0, 8);
  }

  static String _addressText(Map<String, dynamic> address) {
    final direct = address['address_text']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final parts = [
      address['city'],
      address['area'],
      address['street'],
      address['building'],
      address['floor'],
    ]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return parts.join('، ');
  }

  static String _paymentLabel(String method) {
    return switch (method) {
      'cash' => 'نقدًا',
      'card' => 'بطاقة',
      'cliq' => 'CliQ',
      _ => method.isEmpty ? 'غير محدد' : method,
    };
  }

  static String _paymentStatusLabel(String status) {
    return switch (status) {
      'paid' => 'مدفوع',
      'pending' => 'بانتظار الدفع',
      'failed' => 'فشل الدفع',
      _ => status.isEmpty ? 'غير محدد' : status,
    };
  }
}
