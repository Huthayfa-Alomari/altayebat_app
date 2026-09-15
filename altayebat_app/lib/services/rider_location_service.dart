import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'rider_service.dart';

class RiderLocationService {
  RiderLocationService._();

  static final RiderLocationService instance = RiderLocationService._();

  final ValueNotifier<bool> tracking = ValueNotifier<bool>(false);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  final Set<String> _orderIds = <String>{};

  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  DateTime? _lastPushAt;
  bool _pushInFlight = false;

  Position? get lastPosition => _lastPosition;
  Set<String> get orderIds => Set.unmodifiable(_orderIds);

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      lastError.value = 'خدمة GPS مغلقة على الهاتف.';
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      lastError.value = 'يجب السماح للتطبيق باستخدام الموقع أثناء التوصيل.';
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      lastError.value =
          'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق وفعّل الموقع.';
      return false;
    }

    lastError.value = null;
    return true;
  }

  Future<Position?> currentPosition() async {
    if (!await ensurePermission()) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _lastPosition = position;
      lastError.value = null;
      return position;
    } on TimeoutException {
      lastError.value =
          'لم يتمكن الهاتف من تحديد الموقع خلال 20 ثانية. حاول مرة أخرى.';
      return null;
    } catch (_) {
      lastError.value = 'تعذر قراءة GPS من الهاتف.';
      return null;
    }
  }

  Future<void> start(Iterable<String> orderIds) async {
    _orderIds
      ..clear()
      ..addAll(orderIds.where((id) => id.trim().isNotEmpty));

    if (_orderIds.isEmpty) {
      await stop();
      return;
    }

    if (!await ensurePermission()) {
      throw StateError(lastError.value ?? 'GPS_PERMISSION_REQUIRED');
    }

    if (_positionSubscription != null) {
      tracking.value = true;
      final current = _lastPosition;
      if (current != null) await _pushPosition(current, force: true);
      return;
    }

    final initial = await currentPosition();
    if (initial == null) {
      throw StateError(lastError.value ?? 'GPS_UNAVAILABLE');
    }

    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'أسواق الطيبات - التوصيل',
          notificationText: 'يتم تحديث موقعك للزبون أثناء التوصيل.',
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

    tracking.value = true;
    lastError.value = null;
    await _pushPosition(initial, force: true);

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        _lastPosition = position;
        unawaited(_pushPosition(position));
      },
      onError: (Object _) {
        tracking.value = false;
        lastError.value =
            'توقف تحديث GPS. افتح وضع المندوب وشغّل التتبع مرة أخرى.';
      },
      cancelOnError: false,
    );
  }

  Future<void> updateOrders(Iterable<String> orderIds) async {
    final next = orderIds.where((id) => id.trim().isNotEmpty).toSet();
    _orderIds
      ..clear()
      ..addAll(next);
    if (_orderIds.isEmpty) {
      await stop();
      return;
    }
    if (_positionSubscription == null) {
      await start(next);
    }
  }

  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _orderIds.clear();
    tracking.value = false;
    _pushInFlight = false;
  }

  Future<void> _pushPosition(Position position, {bool force = false}) async {
    if (_pushInFlight || _orderIds.isEmpty) return;
    final now = DateTime.now();
    if (!force &&
        _lastPushAt != null &&
        now.difference(_lastPushAt!) < const Duration(seconds: 3)) {
      return;
    }

    _pushInFlight = true;
    try {
      for (final orderId in List<String>.from(_orderIds)) {
        try {
          await RiderService.pushLocation(
            orderId: orderId,
            position: position,
          );
        } catch (error) {
          final message = RiderService.friendlyError(error);
          if (message.contains('ابدأ التوصيل أولًا') ||
              message.contains('غير مسند')) {
            _orderIds.remove(orderId);
          } else {
            lastError.value = message;
          }
        }
      }
      _lastPushAt = now;
      if (_orderIds.isEmpty) {
        await stop();
      } else {
        lastError.value = null;
      }
    } finally {
      _pushInFlight = false;
    }
  }
}
