// lib/features/chat/widgets/chat_animations.dart
//
// Petite bibliothèque d'animations de chat façon
// WhatsApp/Messenger/Telegram : entrée de bulle, coches de statut
// animées (✓ envoyé, ✓✓ délivré, ✓✓ bleu = lu), et les trois points
// "en train d'écrire".

import 'package:flutter/material.dart';

/// Fait glisser + apparaître une bulle de message à son arrivée dans la
/// liste (comme l'effet Telegram/Messenger sur les nouveaux messages).
class AnimatedMessageBubble extends StatelessWidget {
  final Widget child;
  final bool isMine;

  const AnimatedMessageBubble({super.key, required this.child, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: Transform.scale(
              scale: 0.92 + (0.08 * t),
              alignment: isMine ? Alignment.bottomRight : Alignment.bottomLeft,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Coches de statut animées, comme WhatsApp : un check gris (envoyé),
/// deux checks gris (délivré), deux checks bleus (lu). Transition
/// douce entre les états au lieu d'un changement brutal.
class MessageStatusTicks extends StatelessWidget {
  final String status; // 'sent' | 'delivered' | 'read' | 'deleted'
  final Color readColor;

  const MessageStatusTicks({super.key, required this.status, this.readColor = const Color(0xFF34B7F1)});

  @override
  Widget build(BuildContext context) {
    if (status == 'deleted') return const SizedBox.shrink();

    final showDouble = status == 'delivered' || status == 'read';
    final color = status == 'read' ? readColor : Colors.grey;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: Icon(
        showDouble ? Icons.done_all : Icons.done,
        key: ValueKey('$status'),
        size: 15,
        color: color,
      ),
    );
  }
}

/// Bulle "message supprimé" (tombstone), comme WhatsApp/Telegram après
/// un unsend.
class DeletedMessageBubble extends StatelessWidget {
  const DeletedMessageBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: Theme.of(context).disabledColor),
          const SizedBox(width: 6),
          Text('Message supprimé', style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).disabledColor)),
        ],
      ),
    );
  }
}

/// Les trois points animés "X est en train d'écrire..." (Messenger/
/// WhatsApp/Telegram). Piloter la visibilité via
/// PresenceService.typingEvents dans le parent.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final delay = i * 0.2;
              final t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
              final bounce = (t < 0.5) ? t * 2 : (1 - t) * 2;
              return Transform.translate(
                offset: Offset(0, -4 * bounce),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).disabledColor,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Petit point vert "en ligne", avec un fondu léger à l'apparition —
/// à poser en overlay sur l'avatar (cf. PresenceService.isOnline).
class OnlineDot extends StatelessWidget {
  final bool online;
  const OnlineDot({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: online ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
        ),
      ),
    );
  }
}
