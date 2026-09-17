class SocialConfig {
  SocialConfig._();

  // Facebook and Instagram are build-time configurable until the official
  // account URLs are confirmed. This avoids linking users to a similarly named
  // but unrelated business.
  static const String facebookUrl = String.fromEnvironment('FACEBOOK_URL');
  static const String instagramUrl = String.fromEnvironment('INSTAGRAM_URL');

  // Store contact number currently configured in Supabase, normalized for wa.me.
  static const String whatsappNumber = String.fromEnvironment(
    'WHATSAPP_NUMBER',
    defaultValue: '962788570246',
  );
}
