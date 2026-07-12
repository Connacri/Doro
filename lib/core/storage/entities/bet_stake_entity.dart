// lib/core/storage/entities/bet_stake_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class BetStakeEntity {
  int id = 0;

  @Index()
  @Unique()
  final String stakeId;

  @Index()
  final String betId;
  final String optionLabel;
  final String stakerId;
  final String stakerPublicKey;
  final String amount;
  final int timestamp;
  final String signature;

  /// Renseigné seulement après règlement.
  String? payoutAmount; // montant net reçu si gagnant, "0" si perdant/remboursé
  String? payoutTxId; // hash de la Transaction DAG réelle (send) qui a payé

  /// `true` si ce staker devait un paiement (perdant) et que la deadline de
  /// grâce est dépassée sans que `payoutTxId` n'apparaisse dans le DAG —
  /// utilisé pour l'affichage UI et la pénalité de réputation, PAS pour un
  /// blocage cryptographique (impossible sans custodial escrow, voir README).
  bool defaulted;

  BetStakeEntity({
    this.id = 0,
    required this.stakeId,
    required this.betId,
    required this.optionLabel,
    required this.stakerId,
    required this.stakerPublicKey,
    required this.amount,
    required this.timestamp,
    required this.signature,
    this.payoutAmount,
    this.payoutTxId,
    this.defaulted = false,
  });
}
