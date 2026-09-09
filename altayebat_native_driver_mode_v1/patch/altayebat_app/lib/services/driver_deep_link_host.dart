import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/driver_mode_screen.dart';

class DriverDeepLinkHost extends StatefulWidget {
  const DriverDeepLinkHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<DriverDeepLinkHost> createState() => _DriverDeepLinkHostState();
}

class _DriverDeepLinkHostState extends State<DriverDeepLinkHost> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  String? _driverToken;
  String? _lastHandledLink;

  @override
  void initState() {
    super.initState();
    _initLinks();
  }

  Future<void> _initLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (_) {
      // The stream below remains the primary source of deep-link events.
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (_) {},
    );
  }

  void _handleUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'altayebat') return;
    if (uri.host.toLowerCase() != 'driver') return;

    final token = (uri.queryParameters['token'] ?? '').trim();
    if (token.length < 32) return;

    final normalized = uri.toString();
    if (_lastHandledLink == normalized && _driverToken == token) return;

    if (!mounted) return;
    setState(() {
      _lastHandledLink = normalized;
      _driverToken = token;
    });
  }

  void _closeDriverMode() {
    if (!mounted) return;
    setState(() {
      _driverToken = null;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _driverToken;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (token != null)
          DriverModeScreen(
            key: ValueKey(token),
            token: token,
            onClose: _closeDriverMode,
          ),
      ],
    );
  }
}
