import 'package:objectbox/objectbox.dart';

@Entity()
class WalletEntity {
  int id = 0;

  String address;
  String publicKey;
  String balance;

  WalletEntity({
    required this.address,
    required this.publicKey,
    required this.balance,
  });
}