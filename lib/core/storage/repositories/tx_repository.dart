import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../dag/transaction_model.dart';

class TxRepository {
  final List<Transaction> _cache = [];
  static const String _key = 'doro_finalized_txs';

  List<Transaction> all() => List.unmodifiable(_cache);

  Future<void> saveFinalized(Transaction tx) async {
    if (_cache.any((t) => t.id == tx.id)) return;
    _cache.add(tx);
    await _persist();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key);
    if (data == null) return;

    _cache.clear();
    for (final item in data) {
      _cache.add(Transaction.fromJson(jsonDecode(item) as Map<String, dynamic>));
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _cache.map((tx) => jsonEncode(tx.toJson())).toList();
    await prefs.setStringList(_key, data);
  }
}
