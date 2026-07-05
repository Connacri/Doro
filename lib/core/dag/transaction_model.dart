import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// `send` : débite immédiatement le compte émetteur. Ne crédite PERSONNE
/// directement — les fonds restent "en attente" jusqu'à ce que le
/// destinataire les réclame explicitement avec un bloc `receive` (voir
/// plus bas). C'est le modèle "block-lattice" de Nano : chaque compte a
/// sa propre chaîne, et personne d'autre que son propriétaire ne peut
/// jamais y ajouter un bloc.
///
/// `receive` : signé par le DESTINATAIRE, référence explicitement le
/// `send` qu'il réclame (`linkedSendId`). C'est ce bloc, et lui seul, qui
/// crédite le compte. Un `send` ne peut être réclamé qu'une fois.
///
/// Pourquoi ce modèle : dans l'ancienne version (crédit immédiat au
/// moment de l'acceptation du `send`), valider une dépense d'Alice
/// dépendait potentiellement de l'ordre dans lequel un nœud avait déjà
/// vu les crédits ENTRANTS d'Alice provenant d'AUTRES comptes — ordre
/// qui pouvait différer d'un pair à l'autre selon ce qu'ils avaient déjà
/// synchronisé. Avec send/receive, valider un `send` d'Alice ne dépend
/// QUE de la propre chaîne d'Alice (son solde tel qu'ELLE l'a construit,
/// bloc après bloc, dans SON nonce à elle) — jamais de l'historique d'un
/// autre compte. L'ambiguïté d'ordre inter-comptes disparaît par
/// construction, sans avoir besoin d'un consensus global pour la
/// trancher.
enum TxType { send, receive }

/// Une transaction du DAG — un bloc de la chaîne du compte `from`.
///
/// `parents` = hashes des transactions "de pointe" (tips) que celle-ci
/// approuve en les référençant — c'est ce qui construit la chaîne : chaque
/// tx pointe cryptographiquement vers son passé, comme le `previousHash`
/// d'un bloc de blockchain, sauf qu'ici la structure est un graphe (DAG)
/// et non une liste linéaire.
///
/// `hash` est calculé à partir de TOUT le contenu de la tx (y compris ses
/// parents, son type et son éventuel `linkedSendId`). Conséquence directe :
/// modifier ne serait-ce qu'un seul champ d'une transaction passée change
/// son hash, ce qui invalide instantanément toutes les transactions qui la
/// référençaient comme parent. Falsifier l'historique demanderait de
/// re-signer et re-diffuser toute la branche modifiée — irréalisable une
/// fois que d'autres pairs l'ont déjà répliquée et confirmée.
class Transaction {
  final String id;
  final TxType type;
  final String from;
  final String to;
  final BigInt amount;

  /// Hashes des tx parentes approuvées (tip selection façon Tangle).
  final List<String> parents;
  final int timestamp;

  /// Numéro de séquence dans la chaîne DU COMPTE `from`, strictement
  /// croissant, qu'il s'agisse d'un `send` ou d'un `receive` — les deux
  /// partagent la même séquence, exactement comme les blocs successifs
  /// de la chaîne d'un compte Nano. Empêche le rejeu d'un bloc déjà signé.
  final int nonce;

  /// Clé publique Ed25519 (hex) de `from`, incluse pour que n'importe
  /// quel pair puisse vérifier la signature sans échange préalable.
  final String senderPublicKey;

  /// Signature Ed25519 (hex) de `hash` par la clé privée de `from`.
  final String signature;

  /// UNIQUEMENT pour `type == receive` : id du bloc `send` réclamé par ce
  /// bloc. `null`/vide pour un `send`. Un même `send` ne peut être
  /// référencé que par UN SEUL `receive` dans tout le réseau (appliqué
  /// par DagEngine).
  final String? linkedSendId;

  Transaction({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.parents,
    required this.timestamp,
    required this.nonce,
    required this.senderPublicKey,
    required this.signature,
    this.type = TxType.send,
    this.linkedSendId,
  });

  /// Empreinte de contenu : sha256 de tous les champs sauf la signature
  /// elle-même (on signe le hash, on ne peut pas l'inclure dedans).
  /// `type` et `linkedSendId` sont inclus : sans ça, un attaquant pourrait
  /// prendre un bloc valide et le rejouer sous un autre type, ou changer
  /// quel `send` un `receive` prétend réclamer, sans invalider la
  /// signature.
  String get hash {
    final sortedParents = [...parents]..sort();
    final raw = [
      id,
      type.name,
      from,
      to,
      amount.toString(),
      sortedParents.join(','),
      timestamp.toString(),
      nonce.toString(),
      senderPublicKey,
      linkedSendId ?? '',
    ].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "type": type.name,
        "from": from,
        "to": to,
        "amount": amount.toString(),
        "parents": parents,
        "timestamp": timestamp,
        "nonce": nonce,
        "senderPublicKey": senderPublicKey,
        "signature": signature,
        "linkedSendId": linkedSendId,
      };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json["id"] as String,
        type: (json["type"] as String?) == "receive" ? TxType.receive : TxType.send,
        from: json["from"] as String,
        to: json["to"] as String,
        amount: BigInt.parse(json["amount"] as String),
        parents: List<String>.from(json["parents"] ?? const []),
        timestamp: json["timestamp"] as int,
        nonce: json["nonce"] as int? ?? 0,
        senderPublicKey: json["senderPublicKey"] as String? ?? "",
        signature: json["signature"] as String? ?? "",
        linkedSendId: json["linkedSendId"] as String?,
      );
}
