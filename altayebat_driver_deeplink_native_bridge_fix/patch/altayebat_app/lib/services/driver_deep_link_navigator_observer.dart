import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/driver_mode_screen.dart';

class DriverDeepLinkNavigatorObserver extends NavigatorObserver {
  DriverDeepLinkNavigatorObserver._() {
    _init();
  }

  static final DriverDeepLinkNavigatorObserver instance =
      DriverDeepLinkNavigatorObserver._();

  static const MethodChannel _channel = MethodChannel(
    'com.altayebat.app/driver_deep_link',
  );

  String? _pendingToken;
  String? _activeToken;
  bool _opening = false;

  Future<void> _init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final value = call.arguments;
        if (value is String) {
          _handleLink(value);
        }
      }
    });

    try {
      final initialLink = await _channel.invokeMethod<String>('getInitialLink');
      if (initialLink != null && initialLink.isNotEmpty) {
        _handleLink(initialLink);
      }
    } on PlatformException {
      // Native bridge unavailable. The customer app continues normally.
    }
  }

  void _handleLink(String rawLink) {
    final uri = Uri.tryParse(rawLink);
    if (uri == null) return;
    if (uri.scheme.toLowerCase() != 'altayebat') return;
    if (uri.host.toLowerCase() != 'driver') return;

    final token = (uri.queryParameters['token'] ?? '').trim();
    if (token.length < 32) return;

    if (token == _activeToken) return;

    _pendingToken = token;
    _tryOpen();
  }

  void _tryOpen() {
    final nav = navigator;
    final token = _pendingToken;

    if (nav == null || token == null || _opening) return;

    _pendingToken = null;
    _activeToken = token;
    _opening = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await nav.push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            settings: const RouteSettings(name: '/driver-mode'),
            builder: (_) => DriverModeScreen(
              token: token,
              onClose: () {
                final current = navigator;
                if (current != null && current.canPop()) {
                  current.pop();
                }
              },
            ),
          ),
        );
      } finally {
        _opening = false;
        _activeToken = null;

        if (_pendingToken != null) {
          _tryOpen();
        }
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _tryOpen();
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _tryOpen();
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    _tryOpen();
  }
}
