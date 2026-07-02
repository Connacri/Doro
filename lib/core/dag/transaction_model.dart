import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Une transaction du DAG.
///
/// `parents` = hashes des transactions "de pointe" (tips) que celle-ci
/// approuve en les référençant — c'est ce qui construit la chaîne : chaque
/// tx pointe cryptographiquement vers son passé, comme le `previousHash`
/// d'un bloc de blockchain, sauf qu'ici la structure est un graphe (DAG)
/// et non une liste linéaire.
///
/// `hash` est calculé à partir de TOUT le contenu de la tx (y compris ses
/// parents). Conséquence directe : modifier ne serait-ce qu'un seul champ
/// d'une transaction passée change son hash, ce qui invalide instantanément
/// toutes les transactions qui la référençaient comme parent (leur propre
/// hash ne "collerait" plus à la chaîne). Falsifier l'historique demanderait
/// de re-signer et re-diffuser toute la branche modifiée — irréalisable une
/// fois que d'autres pairs l'ont déjà répliquée et confirmée.
class Transaction {
  final String id;
  final String from;
  final String to;
  final BigInt amount;

  /// Hashes des tx parentes approuvées (tip selection façon Tangle).
  final List<String> parents;
  final int timestamp;

  /// Numéro de séquence de l'émetteur (`from`), strictement croissant.
  /// Empêche le rejeu d'une transaction déjà signée (protection anti
  /// double-dépense classique, façon nonce Ethereum).
  final int nonce;

  /// Clé publique Ed25519 (hex) de l'émetteur, incluse pour que n'importe
  /// quel pair puisse vérifier la signature sans échange préalable.
  final String senderPublicKey;

  /// Signature Ed25519 (hex) de `hash` par la clé privée de `from`.
  final String signature;

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
  });

  /// Empreinte de contenu : sha256 de tous les champs sauf la signature
  /// elle-même (on signe le hash, on ne peut pas l'inclure dedans).
  String get hash {
    final sortedParents = [...parents]..sort();
    final raw = [
      id,
      from,
      to,
      amount.toString(),
      sortedParents.join(','),
      timestamp.toString(),
      nonce.toString(),
      senderPublicKey,
    ].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "from": from,
        "to": to,
        "amount": amount.toString(),
        "parents": parents,
        "timestamp": timestamp,
        "nonce": nonce,
        "senderPublicKey": senderPublicKey,
        "signature": signature,
      };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json["id"] as String,
        from: json["from"] as String,
        to: json["to"] as String,
        amount: BigInt.parse(json["amount"] as String),
        parents: List<String>.from(json["parents"] ?? const []),
        timestamp: json["timestamp"] as int,
        nonce: json["nonce"] as int? ?? 0,
        senderPublicKey: json["senderPublicKey"] as String? ?? "",
        signature: json["signature"] as String? ?? "",
      );
}