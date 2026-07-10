// lib/features/boot/boot_terminal_screen.dart
//
// Écran de démarrage façon terminal : affiche en direct tous les logs
// (`Logger.info/warn/error`) depuis le tout premier appel dans
// `main.dart` jusqu'à ce que l'app soit prête — utile en dev pour
// suivre précisément où bloque/traîne le démarrage (ouverture
// ObjectBox, génération/chargement de l'identité, connexion
// signaling, liaison Supabase, etc.), et rassurant en prod pour
// montrer que l'app travaille plutôt qu'un spinner muet.
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/utils/logger.dart';

class BootTerminalScreen extends StatefulWidget {
  /// `true` une fois que l'app peut réellement démarrer (node P2P prêt).
  final bool ready;
  final VoidCallback onContinue;

  const BootTerminalScreen({super.key, required this.ready, required this.onContinue});

  @override
  State<BootTerminalScreen> createState() => _BootTerminalScreenState();
}

class _BootTerminalScreenState extends State<BootTerminalScreen> {
  final _scrollCtrl = ScrollController();
  final List<LogEntry> _lines = [];
  StreamSubscription<LogEntry>? _sub;
  Timer? _autoContinueTimer;

  @override
  void initState() {
    super.initState();
    // Rejoue tout ce qui a déjà été loggé avant que cet écran ne soit
    // monté (ObjectBox.init, NodeIdentity.getOrCreate, etc., appelés
    // dans main.dart / le tout début de _initNode avant le premier
    // setState).
    _lines.addAll(BootLog.entries);
    _sub = BootLog.stream.listen((entry) {
      if (!mounted) return;
      setState(() => _lines.add(entry));
      _scrollToBottom();
    });
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant BootTerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) {
      // Laisse 1.2s pour parcourir les dernières lignes avant de
      // continuer automatiquement — l'utilisateur peut aussi appuyer
      // sur "Continuer" immédiatement.
      _autoContinueTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) widget.onContinue();
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Color _colorFor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFFF5C5C);
      case LogLevel.warn:
        return const Color(0xFFFFD166);
      case LogLevel.info:
        return const Color(0xFF7CFC8A);
    }
  }

  String _prefixFor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return "✗";
      case LogLevel.warn:
        return "!";
      case LogLevel.info:
        return "✓";
    }
  }

  String _time(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _sub?.cancel();
    _autoContinueTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF5C5C), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFFD166), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF7CFC8A), shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  const Text(
                    "doro — boot log",
                    style: TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 12),
                  ),
                  const Spacer(),
                  if (!widget.ready)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: _lines.length,
                itemBuilder: (context, i) {
                  final entry = _lines[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.3),
                        children: [
                          TextSpan(text: "${_time(entry.time)}  ", style: const TextStyle(color: Colors.white30)),
                          TextSpan(text: "${_prefixFor(entry.level)} ", style: TextStyle(color: _colorFor(entry.level), fontWeight: FontWeight.bold)),
                          TextSpan(text: entry.message, style: TextStyle(color: _colorFor(entry.level).withValues(alpha: 0.92))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.ready ? "Prêt." : "Démarrage en cours…",
                      style: const TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  if (widget.ready)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A24), foregroundColor: const Color(0xFF7CFC8A)),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text("Continuer"),
                      onPressed: () {
                        _autoContinueTimer?.cancel();
                        widget.onContinue();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
