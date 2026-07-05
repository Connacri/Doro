/// ⚠️ Historique : cette classe n'est actuellement appelée par aucun code
/// (voir DagEngine, qui gère désormais le rejeu ET le solde de manière
/// centralisée via `_lastNonce` + `LedgerBalances`). Elle contenait un bug
/// bloquant : `isSpent(sender)`/`markSpent(sender)` étaient indexées par
/// expéditeur SEUL, donc la toute première transaction d'un expéditeur
/// aurait marqué son adresse comme "dépensée" pour toujours — bloquant
/// tout envoi ultérieur, même légitime. Corrigé ici (clé sender+nonce)
/// au cas où cette classe serait réutilisée plus tard.
class DoubleSpendChecker {
  final Set<String> _spentKeys = {};

  bool isSpent(String sender, int nonce) {
    return _spentKeys.contains('$sender:$nonce');
  }

  void markSpent(String sender, int nonce) {
    _spentKeys.add('$sender:$nonce');
  }

  bool validate(String sender, int nonce) {
    if (isSpent(sender, nonce)) return false;

    markSpent(sender, nonce);
    return true;
  }
}