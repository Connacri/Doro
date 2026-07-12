// lib/core/prediction/profit_calculator.dart
import '../wallet/token_config.dart';

/// Implémente le calcul de profit d'un marché prédictif "winner takes
/// all" décrit dans la spec :
///
///   - Un contrat gagnant vaut exactement 1 (une unité pleine du token,
///     ici 1 DORO = 10^18 unités atomiques, `TokenConfig.decimals`).
///   - profit = (1 - prixAchat) × nombreDeContrats  SI l'issue se réalise
///   - profit = -prixAchat × nombreDeContrats        SI elle ne se réalise pas
///     (le contrat tombe à 0, la mise initiale est perdue en totalité)
///
/// "Gagnant rafle tout" : ce module ne fait que CALCULER le profit pour
/// affichage — l'argent lui-même ne provient jamais de nulle part : il
/// est physiquement déjà présent dans l'escrow de l'événement (voir
/// EscrowAddress), déposé par TOUS les émetteurs de "complete sets"
/// (1 DORO déposé = 1 part OUI + 1 part NON créées), et redistribué
/// intégralement aux détenteurs de la part gagnante lors du claim — les
/// 0,70 $ "perdus" par les détenteurs de OUI dans l'exemple ne
/// disparaissent pas : ils étaient la contrepartie qui a permis aux
/// détenteurs de NON (qui n'avaient payé que 0,30 $) d'être remboursés
/// 1 $ chacun. Le total versé sur l'événement est toujours strictement
/// égal au total déposé en escrow.
class ProfitCalculator {
  ProfitCalculator._();

  /// 1 DORO en unités atomiques (10^18) — la valeur pleine d'un contrat
  /// gagnant.
  static BigInt get fullContractValue => BigInt.from(10).pow(TokenConfig.decimals);

  /// Profit net PAR CONTRAT, en unités atomiques DORO. Peut être négatif
  /// (perte). `purchasePricePerShare` doit être dans ]0, fullContractValue[.
  static BigInt profitPerContract({
    required BigInt purchasePricePerShare,
    required bool outcomeWon,
  }) {
    return outcomeWon
        ? fullContractValue - purchasePricePerShare // gain net si l'issue se réalise
        : -purchasePricePerShare; // perte totale si elle ne se réalise pas
  }

  /// Profit net total pour une position de `shares` contrats achetés au
  /// même prix moyen `purchasePricePerShare`.
  static BigInt totalProfit({
    required BigInt purchasePricePerShare,
    required BigInt shares,
    required bool outcomeWon,
  }) {
    return profitPerContract(purchasePricePerShare: purchasePricePerShare, outcomeWon: outcomeWon) * shares;
  }

  /// Valeur de règlement PAR CONTRAT si l'issue est connue : 1 DORO
  /// (atomique) si gagnant, 0 sinon. Utile pour afficher "vaut
  /// désormais X" plutôt que juste le delta de profit.
  static BigInt settlementValuePerContract({required bool outcomeWon}) =>
      outcomeWon ? fullContractValue : BigInt.zero;

  /// Rendement en pourcentage (ex: 0.30 $ de gain sur 0.70 $ misé ≈
  /// +42,8 %), pratique pour l'affichage UI. Retourne `null` si le prix
  /// d'achat est nul (division par zéro évitée).
  static double? returnPercent({
    required BigInt purchasePricePerShare,
    required bool outcomeWon,
  }) {
    if (purchasePricePerShare == BigInt.zero) return null;
    final profit = profitPerContract(purchasePricePerShare: purchasePricePerShare, outcomeWon: outcomeWon);
    return profit.toDouble() / purchasePricePerShare.toDouble() * 100;
  }
}
