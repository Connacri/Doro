import 'transaction_model.dart';
import '../wallet/address_generator.dart';
import '../wallet/genesis.dart';

/// Validation STRUCTURELLE d'une transaction (synchrone, pas de crypto
/// asynchrone ici). La vérification de signature elle-même (qui nécessite
/// Ed25519, asynchrone) se fait séparément — voir P2PNode._verifySignature.
class TxValidator {
  bool validate(Transaction tx) {
    if (tx.amount <= BigInt.zero) return false;
    if (tx.to.isEmpty) return false;
    if (tx.signature.isEmpty) return false;
    if (tx.senderPublicKey.isEmpty) return false;

    // Transaction genesis : mintée par le réseau, signée par la clé
    // fondatrice. On saute le check from == senderPublicKey car le from
    // est l'adresse de mint (pas dérivable d'une clé).
    if (Genesis.isMintAddress(tx.from)) {
      return tx.type == TxType.send &&
          tx.amount == Genesis.maxSupply &&
          tx.to == Genesis.genesisAddress &&
          tx.nonce == 0;
    }

    if (tx.from.isEmpty) return false;
    if (tx.nonce < 0) return false;

    // L'adresse déclarée doit être dérivable de la clé publique fournie —
    // sinon n'importe qui pourrait prétendre envoyer depuis l'adresse d'un
    // autre sans en détenir la clé privée. S'applique aux deux types :
    // un `receive` est un bloc de la chaîne du DESTINATAIRE, signé par lui.
    if (AddressGenerator.generate(tx.senderPublicKey) != tx.from) return false;

    if (tx.type == TxType.send) {
      // Un send ne peut pas se payer soi-même.
      if (tx.from == tx.to) return false;
    } else {
      // Un receive doit référencer explicitement le send qu'il réclame.
      if (tx.linkedSendId == null || tx.linkedSendId!.isEmpty) return false;
    }

    return true;
  }
}