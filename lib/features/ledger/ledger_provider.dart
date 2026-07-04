import 'package:flutter/material.dart';
import '../../core/dag/dag_engine.dart';
import '../../core/dag/transaction_model.dart';
import '../../core/p2p/p2p_node.dart';

class LedgerProvider extends ChangeNotifier {
  final P2PNode node;

  LedgerProvider(this.node) {
    // We listen to walletChanges because it covers both commit and finalized
    // through the WalletKernel.
    node.walletChanges.listen((_) => notifyListeners());
  }

  DagEngine get dag => node.dag;

  List<Transaction> get transactions =>
      dag.all()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  bool isFinal(String txId) => dag.isFinal(txId);
  int confirmationsOf(String txId) => dag.confirmersCountOf(txId);
}
