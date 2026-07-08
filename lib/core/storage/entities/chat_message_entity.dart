// lib/core/storage/entities/chat_message_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class ChatMessageEntity {
  int id = 0;

  final String fromId;
  final String text;
  final String timestamp;

  /// Contact de la conversation (que le message soit envoyé ou reçu).
  /// Permet de filtrer l'historique par ami — plus de chat global.
  final String peerKey;

  /// Message status: 'sent', 'delivered', 'read'
  String status;

  ChatMessageEntity({
    this.id = 0,
    required this.fromId,
    required this.text,
    required this.timestamp,
    this.peerKey = '',
    this.status = 'sent',
  });
}