import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/cart_provider.dart';
import 'settings/app_language.dart';
import 'settings/app_preferences.dart';
import 'screens/storefront_root_screen.dart';
import 'services/driver_deep_link_navigator_observer.dart';
import 'services/push_notification_service.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await AppPreferences.load();

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

  runApp(
    AltayebatApp(bootstrapError: bootstrapError, preferences: preferences),
  );

  // Push permission, token retrieval and registration may involve Firebase and
  // network round-trips. They are optional for shopping, so never delay the
  // first rendered frame while they initialize.
  if (bootstrapError == null) {
    unawaited(PushNotificationService.initialize());
  }
}

class AltayebatApp extends StatelessWidget {
  final Object? bootstrapError;
  final AppPreferences? preferences;

  const AltayebatApp({super.key, this.bootstrapError, this.preferences});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider<AppPreferences>(
          create: (_) => preferences ?? AppPreferences(),
        ),
      ],
      child: Consumer<AppPreferences>(
        builder: (context, preferences, _) => MaterialApp(
          navigatorKey: PushNotificationService.navigatorKey,
          navigatorObservers: [DriverDeepLinkNavigatorObserver.instance],
          onGenerateTitle: (context) =>
              AppLanguage.text(context, 'أسواق الطيبات', 'Altayebat Markets'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: preferences.themeMode,
          locale: preferences.locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: bootstrapError != null
              ? const _BootstrapErrorScreen()
              : const StorefrontRootScreen(),
        ),
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
