import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../wallet/wallet_core.dart';
import '../../wallet/wallet_model.dart';

class WalletRepository {
  final List<Wallet> _cache = [];
  static const String _key = 'doro_wallets';

  Future<void> save(Wallet w) async {
    _cache.add(w);
    await _persist();
  }

  List<Wallet> all() => List.unmodifiable(_cache);

  Future<void> syncFromCore(WalletCore core) async {
    _cache.clear();
    _cache.addAll(core.all());
    await _persist();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key);
    if (data != null) {
      _cache.clear();
      for (final item in data) {
        final json = jsonDecode(item);
        _cache.add(Wallet(
          address: json['address'],
          publicKey: json['publicKey'],
          balance: BigInt.parse(json['balance']),
          nonce: json['nonce'] as int? ?? 0,
        ));
      }
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _cache.map((w) => jsonEncode(w.toJson())).toList();
    await prefs.setStringList(_key, data);
  }
}