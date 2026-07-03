import 'transaction_model.dart';

/// Une tx devient "finale" quand suffisamment de PAIRS DISTINCTS l'ont
/// validée et confirmée (jamais l'émetteur lui-même — voir P2PNode, où
/// une confirmation ne peut venir que d'un message reçu du réseau).
///
/// `requiredConfirmations` est volontairement bas par défaut (1) car un
/// petit réseau de test n'a parfois qu'un seul pair connecté ; augmente
/// cette valeur pour un réseau plus large où tu veux un vrai quorum avant
/// de créditer un solde.
class FinalityEngine {
  final Map<String, int> confirmations = {};
  final int requiredConfirmations;

  FinalityEngine({this.requiredConfirmations = 1});

  void addConfirmation(String txId) {
    confirmations[txId] = (confirmations[txId] ?? 0) + 1;
  }

  void markFinalized(String txId) {
    confirmations[txId] = requiredConfirmations;
  }

  int confirmationsOf(String txId) => confirmations[txId] ?? 0;

  bool isFinal(String txId) {
    return confirmationsOf(txId) >= requiredConfirmations;
  }

  void prune(List<Transaction> ledger) {
    ledger.removeWhere((tx) => !isFinal(tx.id));
  }
}