import 'package:objectbox/objectbox.dart';

@Entity()
class WalletEntity {
  int id = 0;

  @Index()
  final String address;
  final String publicKey;
  final String balance;

  WalletEntity({
    this.id = 0,
    required this.address,
    required this.publicKey,
    required this.balance,
  });
}
