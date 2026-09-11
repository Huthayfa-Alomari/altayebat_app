import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/cart_provider.dart';
import 'screens/home_screen.dart';
import 'services/driver_deep_link_navigator_observer.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? bootstrapError;
  try {
    await SupabaseService.initialize();

    // Catalogue RLS is available to authenticated users. Create an anonymous
    // session silently so first-time customers can browse immediately without
    // seeing a registration/profile gate. Name and phone are collected only
    // when they continue to checkout.
    if (!SupabaseService.isSignedIn) {
      final response = await Supabase.instance.client.auth.signInAnonymously();
      if (response.user == null) {
        throw StateError('تعذر بدء جلسة التسوق');
      }
    }
  } catch (error, stackTrace) {
    bootstrapError = error;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'altayebat bootstrap',
      ),
    );
  }

  runApp(AltayebatApp(bootstrapError: bootstrapError));
}

class AltayebatApp extends StatelessWidget {
  final Object? bootstrapError;

  const AltayebatApp({super.key, this.bootstrapError});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        navigatorObservers: [DriverDeepLinkNavigatorObserver.instance],
        title: 'أسواق الطيبات',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: bootstrapError != null
            ? const _BootstrapErrorScreen()
            : const HomeScreen(),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 52,
                  color: AppColors.primary,
                ),
                SizedBox(height: 16),
                Text(
                  'تعذر تشغيل التطبيق',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'تأكد من اتصال الإنترنت ثم أغلق التطبيق وافتحه مرة ثانية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
