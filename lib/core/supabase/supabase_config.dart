// lib/core/supabase/supabase_config.dart
//
// URL et clé anon Supabase, injectées à la compilation via --dart-define
// ou chargées depuis assets/config.json au démarrage en développement local.
import 'dart:convert';
import 'package:flutter/services.dart';

class SupabaseConfig {
  static String url = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static String anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static String serviceRoleKey = const String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY', defaultValue: '');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (url.isEmpty || anonKey.isEmpty || serviceRoleKey.isEmpty) {
      try {
        final content = await rootBundle.loadString('assets/config.json');
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        if (jsonMap.containsKey('SUPABASE_URL') && jsonMap['SUPABASE_URL'] != null) {
          url = jsonMap['SUPABASE_URL'].toString();
        }
        if (jsonMap.containsKey('SUPABASE_ANON_KEY') && jsonMap['SUPABASE_ANON_KEY'] != null) {
          anonKey = jsonMap['SUPABASE_ANON_KEY'].toString();
        }
        if (jsonMap.containsKey('SUPABASE_SERVICE_ROLE_KEY') && jsonMap['SUPABASE_SERVICE_ROLE_KEY'] != null) {
          serviceRoleKey = jsonMap['SUPABASE_SERVICE_ROLE_KEY'].toString();
        }
      } catch (_) {
      }
    }
  }
}
