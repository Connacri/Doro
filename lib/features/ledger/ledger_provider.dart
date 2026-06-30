import 'package:flutter/material.dart';
import '../../core/sync/dag_engine.dart';
import 'transaction_model.dart';

class LedgerProvider extends ChangeNotifier {
  final DAGEngine dag = DAGEngine();

  void addTx(Transaction tx) {
    dag.add(tx);
    notifyListeners();
  }

  List<Transaction> get ledger => dag.ledger;
}