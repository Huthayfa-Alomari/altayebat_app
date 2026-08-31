class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wfvuojrhxewogdnynytf.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_GZV5SCGFY-32O3fz3ciUkg_2B6hYckJ',
  );

  static const String storeId = String.fromEnvironment(
    'STORE_ID',
    defaultValue: '61e6f35d-7004-4a33-948c-b297ba446678',
  );

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty || storeId.isEmpty) {
      throw StateError(
        'Missing app configuration. Provide SUPABASE_URL, SUPABASE_ANON_KEY and STORE_ID using --dart-define.',
      );
    }
  }
}
