import 'dart:io';
import 'dart:convert';

void main() {
  File? keysFile;
  if (File('key.txt').existsSync()) {
    keysFile = File('key.txt');
  } else if (File('keys.txt').existsSync()) {
    keysFile = File('keys.txt');
  }

  if (keysFile == null) {
    print('Error: Neither key.txt nor keys.txt found in the root directory.');
    exit(1);
  }

  final lines = keysFile.readAsLinesSync();
  String? url;
  String? anonKey;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.toLowerCase().contains('project url')) {
      // The next non-empty line contains the URL
      for (int j = i + 1; j < lines.length; j++) {
        final nextLine = lines[j].trim();
        if (nextLine.isNotEmpty) {
          url = nextLine;
          break;
        }
      }
    } else if (line.toLowerCase().contains('anon public')) {
      // The next non-empty line contains the anon key
      for (int j = i + 1; j < lines.length; j++) {
        final nextLine = lines[j].trim();
        if (nextLine.isNotEmpty) {
          anonKey = nextLine;
          break;
        }
      }
    } else if (line.startsWith('SUPABASE_URL=')) {
      url = line.substring('SUPABASE_URL='.length).trim();
    } else if (line.startsWith('SUPABASE_ANON_KEY=')) {
      anonKey = line.substring('SUPABASE_ANON_KEY='.length).trim();
    }
  }

  if (url == null || anonKey == null) {
    print('Error: Could not extract project URL and anon public key from \${keysFile.path}');
    exit(1);
  }

  // Create assets directory if it doesn't exist
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync();
  }

  // Write to assets/config.json
  final configJson = File('assets/config.json');
  configJson.writeAsStringSync(json.encode({
    'SUPABASE_URL': url,
    'SUPABASE_ANON_KEY': anonKey,
  }));
  print('Successfully wrote assets/config.json');

  // Write to .env
  final envFile = File('.env');
  envFile.writeAsStringSync('SUPABASE_URL=\$url\nSUPABASE_ANON_KEY=\$anonKey\n');
  print('Successfully wrote .env');
}
