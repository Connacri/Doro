// lib/features/boot/boot_terminal_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/utils/logger.dart';
import '../../shared/theme/colors.dart';

class BootTerminalScreen extends StatefulWidget {
  /// `true` une fois que l'app peut réellement démarrer (node P2P prêt).
  final bool ready;
  final VoidCallback onContinue;

  const BootTerminalScreen({super.key, required this.ready, required this.onContinue});

  @override
  State<BootTerminalScreen> createState() => _BootTerminalScreenState();
}

class _BootTerminalScreenState extends State<BootTerminalScreen> with SingleTickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  final List<LogEntry> _lines = [];
  StreamSubscription<LogEntry>? _sub;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _lines.addAll(BootLog.entries);
    _sub = BootLog.stream.listen((entry) {
      if (!mounted) return;
      setState(() => _lines.add(entry));
      _scrollToBottom();
    });
    _scrollToBottom();
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

  Color _badgeBgColorFor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return const Color(0x25FF4D4D);
      case LogLevel.warn:
        return const Color(0x25FFD166);
      case LogLevel.info:
        return const Color(0x206C5CE7);
    }
  }

  Color _badgeTextColorFor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return const Color(0xFFFF4D4D);
      case LogLevel.warn:
        return const Color(0xFFFFD166);
      case LogLevel.info:
        return const Color(0xFF9E92EC);
    }
  }

  String _badgeTextFor(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return "ERR";
      case LogLevel.warn:
        return "WRN";
      case LogLevel.info:
        return "INF";
    }
  }

  String _time(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _sub?.cancel();
    _pulseController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090E),
      body: Stack(
        children: [
          // Background reflection glow 1: Top-Left (Indigo/Purple)
          Positioned(
            top: -120,
            left: -120,
            width: 380,
            height: 380,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Background reflection glow 2: Top-Right (Teal/Cyan)
          Positioned(
            top: 150,
            right: -100,
            width: 320,
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0x1000D084),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Background reflection glow 3: Bottom-Left (Crimson/Pink)
          Positioned(
            bottom: -150,
            left: 20,
            width: 380,
            height: 380,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0x12FF4D4D),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Floating Terminal Container
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xD80E0E18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 32,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Terminal Titlebar
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    // Window Control Buttons
                                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEE6A5F), shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFF5BE4F), shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF61C454), shape: BoxShape.circle)),
                                    const SizedBox(width: 16),
                                    Text(
                                      "doro-core@node:~ boot.sh",
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.45),
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Status Badge on the right
                                    AnimatedBuilder(
                                      animation: _pulseController,
                                      builder: (context, child) {
                                        final color = widget.ready ? const Color(0xFF00D084) : AppColors.primary;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: color.withValues(alpha: 0.25)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: color.withValues(alpha: 0.5 * _pulseController.value),
                                                      blurRadius: 6 * _pulseController.value,
                                                      spreadRadius: 1 * _pulseController.value,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                widget.ready ? "ONLINE" : "BOOTING",
                                                style: TextStyle(
                                                  color: color,
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.5,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(color: Colors.white10, height: 1),
                              // Terminal Log List Area
                              Expanded(
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                                  child: ListView.builder(
                                    controller: _scrollCtrl,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _lines.length + 1,
                                    itemBuilder: (context, i) {
                                      if (i == _lines.length) {
                                        // Blinking Terminal Prompt
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                                          child: Row(
                                            children: [
                                              Text(
                                                widget.ready ? "doro@core:~\$ ready" : "doro@core:~\$ loading…",
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12,
                                                  color: Colors.white.withValues(alpha: 0.35),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              AnimatedBuilder(
                                                animation: _pulseController,
                                                builder: (context, child) {
                                                  return Opacity(
                                                    opacity: _pulseController.value > 0.5 ? 1.0 : 0.0,
                                                    child: const Text(
                                                      "▋",
                                                      style: TextStyle(color: AppColors.primary, fontSize: 12),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      final entry = _lines[i];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45),
                                            children: [
                                              TextSpan(
                                                text: "${_time(entry.time)}  ",
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.22)),
                                              ),
                                              WidgetSpan(
                                                alignment: PlaceholderAlignment.middle,
                                                child: Container(
                                                  margin: const EdgeInsets.only(right: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: _badgeBgColorFor(entry.level),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    _badgeTextFor(entry.level),
                                                    style: TextStyle(
                                                      color: _badgeTextColorFor(entry.level),
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.w800,
                                                      fontFamily: 'monospace',
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              TextSpan(
                                                text: entry.message,
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom Area (Controls & Status)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, left: 4, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.ready ? "System ready." : "Running boot scripts…",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        // Premium Entry Button Animation
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                                ),
                                child: child,
                              ),
                            );
                          },
                          child: widget.ready
                              ? Container(
                                  key: const ValueKey("btn_continue"),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        Color(0xFF8C7FFA),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                    label: const Text(
                                      "Continuer",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                                    ),
                                    onPressed: widget.onContinue,
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey("btn_placeholder")),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
