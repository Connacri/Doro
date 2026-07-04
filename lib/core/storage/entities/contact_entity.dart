import 'package:objectbox/objectbox.dart';

@Entity()
class ContactEntity {
  int id = 0;

  @Index()
  final String publicKey;
  final String name;

  ContactEntity({
    this.id = 0,
    required this.publicKey,
    required this.name,
  });
}
