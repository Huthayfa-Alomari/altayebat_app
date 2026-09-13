import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../screens/order_tracking_screen.dart';
import 'growth_service.dart';

class PushNotificationService {
  PushNotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _initialized = false;
  static String? _currentToken;

  static bool get isConfigured => _firebaseOptions != null;

  static FirebaseOptions? get _firebaseOptions {
    if (!AppConfig.hasFirebaseBaseConfig) return null;

    if (Platform.isAndroid) {
      if (AppConfig.firebaseAndroidAppId.trim().isEmpty) return null;
      return FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAndroidAppId,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        projectId: AppConfig.firebaseProjectId,
      );
    }

    if (Platform.isIOS) {
      if (AppConfig.firebaseIosAppId.trim().isEmpty) return null;
      return FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseIosAppId,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        projectId: AppConfig.firebaseProjectId,
        iosBundleId: AppConfig.firebaseIosBundleId,
      );
    }

    return null;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    final options = _firebaseOptions;
    if (options == null) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
      messaging.onTokenRefresh.listen((token) async {
        _currentToken = token;
        await _registerToken(token);
      });

      await syncCurrentToken();

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleOpenedMessage(initialMessage);
        });
      }

      _initialized = true;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'altayebat push notifications',
          context: ErrorDescription('while initializing Firebase Messaging'),
        ),
      );
    }
  }

  static Future<void> syncCurrentToken() async {
    if (_firebaseOptions == null || Firebase.apps.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;
      _currentToken = token;
      await _registerToken(token);
    } catch (_) {
      // APNs/FCM can be temporarily unavailable. Token refresh will retry later.
    }
  }

  static Future<void> _registerToken(String token) {
    return GrowthService.registerPushToken(
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'أسواق الطيبات';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        'لديك تحديث جديد';
    final orderId = message.data['order_id']?.toString() ?? '';

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        action: orderId.isEmpty
            ? null
            : SnackBarAction(
                label: 'فتح',
                onPressed: () => _openOrder(orderId),
              ),
      ),
    );
  }

  static Future<void> _handleOpenedMessage(RemoteMessage message) async {
    final notificationId = message.data['notification_id']?.toString() ?? '';
    if (notificationId.isNotEmpty) {
      await GrowthService.markNotificationRead(notificationId);
    }

    final orderId = message.data['order_id']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      _openOrder(orderId);
    }
  }

  static void _openOrder(String orderId) {
    if (orderId.trim().isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOrder(orderId));
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(orderId: orderId),
      ),
    );
  }
}
