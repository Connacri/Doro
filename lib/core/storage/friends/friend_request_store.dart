import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum FriendRequestDirection { sent, received }

class FriendRequest {
  final String publicKey;
  final String? name;
  final FriendRequestDirection direction;
  final String time;

  FriendRequest({required this.publicKey, this.name, required this.direction, required this.time});
}

/// Suivi des demandes d'ami en attente (envoyées et reçues).
///
/// ⚠️ Même contrainte technique que pour les transactions : pas d'accès
/// à `build_runner` ici, donc pas de nouvelle entité ObjectBox propre
/// pour ça. `shared_preferences` (déjà une dépendance du projet) est un
/// choix délibéré et raisonnable pour ce cas précis : c'est un état
/// transitoire et léger (quelques demandes en attente, pas un historique
/// à faire grossir indéfiniment), contrairement au ledger de
/// transactions qui, lui, mérite un vrai stockage structuré.
///
/// Les AMIS CONFIRMÉS restent dans `ContactRepository`/`ContactEntity`
/// comme avant — cette classe ne gère QUE l'état "en attente".
class FriendRequestStore {
  static const _prefsKey = 'doro_friend_requests_v1';
  Map<String, Map<String, String>> _data = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _data = decoded.map((k, v) => MapEntry(k, Map<String, String>.from(v as Map)));
    } catch (_) {
      _data = {};
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_data));
  }

  bool hasSent(String publicKey) => _data[publicKey]?['direction'] == 'sent';
  bool hasReceived(String publicKey) => _data[publicKey]?['direction'] == 'received';
  String? nameOf(String publicKey) {
    final n = _data[publicKey]?['name'];
    return (n == null || n.isEmpty) ? null : n;
  }

  List<FriendRequest> sent() => _entriesWhere('sent');
  List<FriendRequest> received() => _entriesWhere('received');

  List<FriendRequest> _entriesWhere(String direction) {
    return _data.entries.where((e) => e.value['direction'] == direction).map((e) => FriendRequest(
          publicKey: e.key,
          name: (e.value['name']?.isEmpty ?? true) ? null : e.value['name'],
          direction: direction == 'sent' ? FriendRequestDirection.sent : FriendRequestDirection.received,
          time: e.value['time'] ?? '',
        )).toList();
  }

  Future<void> addSent(String publicKey, {String? name}) async {
    _data[publicKey] = {'direction': 'sent', 'name': name ?? '', 'time': DateTime.now().toIso8601String()};
    await _persist();
  }

  Future<void> addReceived(String publicKey, {String? name}) async {
    _data[publicKey] = {'direction': 'received', 'name': name ?? '', 'time': DateTime.now().toIso8601String()};
    await _persist();
  }

  Future<void> remove(String publicKey) async {
    if (_data.remove(publicKey) != null) await _persist();
  }
}
