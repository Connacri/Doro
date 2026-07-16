// lib/core/supabase/supabase_config.dart
//
// URL et clés Supabase, injectées à la compilation via --dart-define
// ou chargées depuis assets/config.json ou key.txt au démarrage.
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/services.dart';

class SupabaseConfig {
  static String url = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static String anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static String serviceRoleKey = const String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY', defaultValue: '');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (url.isEmpty || anonKey.isEmpty || serviceRoleKey.isEmpty) {
      await _loadFromAssetConfig();
    }
    if (url.isEmpty || anonKey.isEmpty || serviceRoleKey.isEmpty) {
      _loadFromKeyTxt();
    }
  }

  static Future<void> _loadFromAssetConfig() async {
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

  static void _loadFromKeyTxt() {
    try {
      final file = File('key.txt');
      if (!file.existsSync()) return;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        if (line.startsWith('https://') && url.isEmpty) {
          url = line;
        } else if (line == 'anon public' && i + 1 < lines.length) {
          anonKey = lines[i + 1].trim();
        } else if (line == 'service_role secret' && i + 1 < lines.length) {
          serviceRoleKey = lines[i + 1].trim();
        }
      }
    } catch (_) {
    }
  }
}
