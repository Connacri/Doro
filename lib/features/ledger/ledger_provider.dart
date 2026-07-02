import 'package:flutter/material.dart';
import '../../core/dag/dag_engine.dart';
import '../../core/dag/transaction_model.dart';
import '../../core/p2p/p2p_node.dart';

class LedgerProvider extends ChangeNotifier {
  final P2PNode node;

  LedgerProvider(this.node) {
    final previousOnCommit = dag.onCommit;
    dag.onCommit = (tx) {
      previousOnCommit?.call(tx);
      notifyListeners();
    };

    final previousOnFinalized = dag.onFinalized;
    dag.onFinalized = (tx) {
      previousOnFinalized?.call(tx);
      notifyListeners();
    };
  }

  DagEngine get dag => node.dag;

  void addTx(Transaction tx) {
    dag.add(tx);
  }

  List<Transaction> get transactions =>
      dag.all()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  bool isFinal(String txId) => dag.isFinal(txId);
  int confirmationsOf(String txId) => dag.confirmersCountOf(txId);
}