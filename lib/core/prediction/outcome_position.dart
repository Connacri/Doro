// lib/core/prediction/outcome_position.dart

/// Solde de parts détenues par `holderAddress` sur l'issue `outcome` de
/// l'événement `eventId`. `sharesClaimed` compte les parts déjà réglées
/// après résolution (1 DORO chacune) — empêche une double réclamation.
///
/// Une "part" = un contrat conditionnel valant exactement 1 DORO SI son
/// issue se réalise, 0 sinon. Émise uniquement par paire complète
/// (1 OUI + 1 NON pour 1 DORO déposé en escrow, voir
/// PredictionMarketKernel.mintCompleteSet) — c'est cette contrainte qui
/// garantit que la caisse d'escrow contient toujours exactement de quoi
/// payer 1 DORO à chaque part gagnante en circulation, ni plus ni moins.
class OutcomePosition {
  final String eventId;
  final String outcome; // "yes" | "no"
  final String holderAddress;
  final BigInt shares;
  final BigInt sharesClaimed;

  const OutcomePosition({
    required this.eventId,
    required this.outcome,
    required this.holderAddress,
    required this.shares,
    required this.sharesClaimed,
  });

  BigInt get sharesClaimable => shares - sharesClaimed;

  OutcomePosition copyWith({BigInt? shares, BigInt? sharesClaimed}) => OutcomePosition(
        eventId: eventId,
        outcome: outcome,
        holderAddress: holderAddress,
        shares: shares ?? this.shares,
        sharesClaimed: sharesClaimed ?? this.sharesClaimed,
      );
}
