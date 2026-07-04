import 'package:objectbox/objectbox.dart';

@Entity()
class ChatMessageEntity {
  int id = 0;

  final String fromId;
  final String text;
  final String timestamp;

  ChatMessageEntity({
    this.id = 0,
    required this.fromId,
    required this.text,
    required this.timestamp,
  });
}
