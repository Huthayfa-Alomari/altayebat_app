import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/driver_mode_screen.dart';

class DriverDeepLinkNavigatorObserver extends NavigatorObserver {
  DriverDeepLinkNavigatorObserver._() {
    _init();
  }

  static final DriverDeepLinkNavigatorObserver instance =
      DriverDeepLinkNavigatorObserver._();

  final AppLinks _appLinks = AppLinks();
  String? _pendingToken;
  String? _activeToken;
  bool _opening = false;

  Future<void> _init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (_) {}

    _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (_) {},
    );
  }

  void _handleUri(Uri uri) {
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
}
