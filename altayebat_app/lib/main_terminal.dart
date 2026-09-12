import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/terminal_home_screen.dart';
import 'services/supabase_service.dart';
import 'services/terminal_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? bootstrapError;
  try {
    await SupabaseService.initialize();
  } catch (error, stackTrace) {
    bootstrapError = error;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'altayebat terminal bootstrap',
      ),
    );
  }

  runApp(AltayebatTerminalApp(bootstrapError: bootstrapError));
}

class AltayebatTerminalApp extends StatelessWidget {
  final Object? bootstrapError;

  const AltayebatTerminalApp({super.key, this.bootstrapError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الطيبات - جهاز الموظف',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: bootstrapError == null
          ? const _TerminalAuthGate()
          : const _TerminalBootstrapError(),
    );
  }
}

class _TerminalAuthGate extends StatefulWidget {
  const _TerminalAuthGate();

  @override
  State<_TerminalAuthGate> createState() => _TerminalAuthGateState();
}

class _TerminalAuthGateState extends State<_TerminalAuthGate> {
  bool _checking = true;
  bool _authorized = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final authorized = await TerminalService.currentUserIsStoreAdmin();
      if (!mounted) return;
      setState(() {
        _authorized = authorized;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_authorized) {
      return TerminalHomeScreen(
        onSignedOut: () => setState(() => _authorized = false),
      );
    }
    return _TerminalLogin(
      onAuthorized: () => setState(() => _authorized = true),
    );
  }
}

class _TerminalLogin extends StatefulWidget {
  final VoidCallback onAuthorized;

  const _TerminalLogin({required this.onAuthorized});

  @override
  State<_TerminalLogin> createState() => _TerminalLoginState();
}

class _TerminalLoginState extends State<_TerminalLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'اكتب بريد الموظف وكلمة المرور.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signOut();
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final isAdmin = await TerminalService.currentUserIsStoreAdmin();
      if (!isAdmin) {
        await Supabase.instance.client.auth.signOut();
        throw StateError('هذا الحساب غير مخول لإدارة فرع الطيبات.');
      }

      if (!mounted) return;
      widget.onAuthorized();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error
            .toString()
            .replaceFirst('AuthException(message: ', '')
            .replaceFirst('Bad state: ', '')
            .replaceAll(')', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.point_of_sale_rounded, size: 64),
                  const SizedBox(height: 18),
                  const Text(
                    'جهاز موظف أسواق الطيبات',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'طلبات • طباعة SUNMI • باركود • مخزون',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'بريد الموظف',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: const Text('دخول الموظف'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalBootstrapError extends StatelessWidget {
  const _TerminalBootstrapError();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'تعذر تشغيل جهاز الموظف. تأكد من الإنترنت وإعدادات Supabase ثم أعد فتح التطبيق.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
