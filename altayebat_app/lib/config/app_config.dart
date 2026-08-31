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
