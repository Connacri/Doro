// lib/core/supabase/supabase_config.dart
//
// URL et clé anon Supabase, injectées à la compilation via --dart-define
// (jamais codées en dur). anon key = clé PUBLIQUE par design, protégée
// uniquement par les policies RLS — voir supabase/migrations/.
//
// Exemple de build :
//   flutter run \
//     --dart-define=SUPABASE_URL=https://rwzsnlfuqmfxouhfbeoi.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=<ta_clé_anon>
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
