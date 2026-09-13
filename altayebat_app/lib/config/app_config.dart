class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wfvuojrhxewogdnynytf.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_GZV5SCGFY-32O3fz3ciUkg_2B6hYckJ',
  );

  static const String storeId = String.fromEnvironment(
    'STORE_ID',
    defaultValue: '61e6f35d-7004-4a33-948c-b297ba446678',
  );

  // Firebase is intentionally configured through dart-defines rather than
  // committing google-services.json / GoogleService-Info.plist to the repo.
  // The app remains fully usable when these values are absent; only remote push
  // delivery is disabled until production Firebase credentials are supplied.
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
  );
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String firebaseAndroidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const String firebaseIosAppId = String.fromEnvironment(
    'FIREBASE_IOS_APP_ID',
  );
  static const String firebaseIosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.altayebat.app',
  );

  static bool get hasFirebaseBaseConfig =>
      firebaseApiKey.trim().isNotEmpty &&
      firebaseProjectId.trim().isNotEmpty &&
      firebaseMessagingSenderId.trim().isNotEmpty;

  static void validate() {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('SUPABASE_URL غير صالح');
    }

    if (!supabasePublishableKey.startsWith('sb_publishable_')) {
      throw StateError('استخدم Supabase publishable key فقط داخل التطبيق');
    }

    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (!uuidPattern.hasMatch(storeId)) {
      throw StateError('STORE_ID غير صالح');
    }
  }
}
