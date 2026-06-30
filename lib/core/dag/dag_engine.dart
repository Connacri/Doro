import '../crypto/ed25519.dart';
import 'transaction_model.dart';

class DagEngine {
  final Map<String, Transaction> ledger = {};
  final Set<String> tips = {}; // The current tips of the DAG

  Function(Transaction tx)? onCommit;

  Future<bool> addTransaction(Transaction tx) async {
    // 1. Validate Hash
    final expectedHash = Transaction.calculateHash(
      from: tx.from,
      to: tx.to,
      amount: tx.amount,
      parents: tx.parents,
      timestamp: tx.timestamp,
      publicKey: tx.publicKey,
    );
    if (tx.id != expectedHash) return false;

    // 2. Validate Signature
    final isSignatureValid = await Crypto.verify(tx.id, tx.signature, tx.publicKey);
    if (!isSignatureValid) return false;

    // 3. Check Parents exist (except for genesis)
    if (ledger.isNotEmpty) {
      for (final parent in tx.parents) {
        if (!ledger.containsKey(parent)) return false;
      }
    }

    // 4. Update Ledger and Tips
    ledger[tx.id] = tx;
    
    // Remove parents from tips and add new tx as tip
    for (final parent in tx.parents) {
      tips.remove(parent);
    }
    tips.add(tx.id);

    onCommit?.call(tx);
    return true;
  }

  List<String> getTips() {
    if (tips.isEmpty && ledger.isNotEmpty) {
       // Fallback to latest transaction if tips are somehow empty
       return [ledger.keys.last];
    }
    return tips.toList();
  }

  List<Transaction> all() => ledger.values.toList();
}
