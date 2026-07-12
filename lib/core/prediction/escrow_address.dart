// lib/core/prediction/escrow_address.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Dérive, pour un `eventId` donné, une adresse d'escrow déterministe —
/// calculable indépendamment par tous les pairs, sans coordination.
///
/// Propriété clé : cette adresse n'est la clé publique d'AUCUNE paire
/// Ed25519 réellement générée (c'est un hash, pas un point sur la
/// courbe). Personne — pas même le créateur de l'event — ne peut donc
/// jamais produire une transaction `send` valide DEPUIS cette adresse
/// via le mécanisme de signature normal : c'est ce qui rend les DORO
/// déposés ici réellement bloqués jusqu'à la résolution, exactement
/// comme un contrat d'escrow on-chain sans clé d'administrateur.
///
/// Les DORO qui y entrent (via un `send` normal, parfaitement valide
/// pour DagEngine — n'importe qui peut envoyer À n'importe quelle
/// adresse) n'en ressortent que par la règle protocolaire de paiement
/// des gagnants appliquée localement par chaque pair après résolution
/// (voir PredictionMarketKernel._applyWinnerPayout), exactement comme
/// l'exception déjà codée pour `Genesis.isMintAddress` dans DagEngine —
/// aucune modification du moteur DAG n'est nécessaire.
class EscrowAddress {
  EscrowAddress._();

  static String forEvent(String eventId) {
    final digest = crypto.sha256.convert(utf8.encode("doro-prediction-escrow:$eventId"));
    return "0xESCROW$digest";
  }

  /// Une adresse d'escrow ne peut jamais coïncider avec une vraie adresse
  /// wallet (préfixe distinct et non-hexadécimal après "0x"), donc
  /// aucune vérification de clé publique ne pourra jamais la faire
  /// passer pour un compte utilisateur normal.
  static bool isEscrow(String address) => address.startsWith("0xESCROW");
}
