import 'package:shared_preferences/shared_preferences.dart';
import 'id_generator.dart';

/// Génère (une seule fois) puis persiste l'identifiant du node local.
///
/// Avant ce fix, `P2PNode` recevait un nodeId reconstruit à chaque
/// `initState()` (`"volte-${DateTime.now().millisecondsSinceEpoch}"`),
/// donc jamais stable : impossible de partager un ID ou un QR code fiable,
/// puisqu'il changeait à chaque hot restart / relance de l'app.
class NodeIdentity {
  static const _key = 'volte_node_id';

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = "volte-${IdGenerator.shortId(DateTime.now().toIso8601String())}";
    await prefs.setString(_key, id);
    return id;
  }
}