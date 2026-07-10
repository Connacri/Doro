import "dart:async";
import "package:flutter/foundation.dart";

enum LogLevel { info, warn, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  const LogEntry(this.time, this.level, this.message);
}

/// Buffer en mémoire de TOUS les logs de l'app, depuis le tout premier
/// appel (avant même `runApp`, cf. `main.dart`) jusqu'à maintenant —
/// consommé par l'écran "terminal" affiché au démarrage
/// (`BootTerminalScreen`). Bornée à [_maxEntries] pour ne pas grossir
/// indéfiniment sur une session longue.
class BootLog {
  static final List<LogEntry> _entries = [];
  static const int _maxEntries = 1000;

  static final _controller = StreamController<LogEntry>.broadcast();
  static Stream<LogEntry> get stream => _controller.stream;
  static List<LogEntry> get entries => List.unmodifiable(_entries);

  static void _push(LogLevel level, String message) {
    final entry = LogEntry(DateTime.now(), level, message);
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    _controller.add(entry);
  }
}

class Logger {
  static void info(String msg) {
    debugPrint("[INFO] $msg");
    BootLog._push(LogLevel.info, msg);
  }

  static void warn(String msg) {
    debugPrint("[WARN] $msg");
    BootLog._push(LogLevel.warn, msg);
  }

  static void error(String msg) {
    debugPrint("[ERROR] $msg");
    BootLog._push(LogLevel.error, msg);
  }
}