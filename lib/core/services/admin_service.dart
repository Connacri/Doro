// lib/core/services/admin_service.dart
//
// Vérifie si l'utilisateur courant est admin (colonne profiles.is_admin,
// voir migration 0005). Utilisé pour n'afficher les boutons "Créer un
// pari" / "Créer une prédiction" qu'aux admins — la policy RLS côté
// Supabase est la véritable barrière de sécurité, ceci n'est qu'un
// confort UI (ne jamais faire confiance au client seul).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  static final AdminService instance = AdminService._();
  AdminService._();

  bool? _cachedIsAdmin;

  Future<bool> isCurrentUserAdmin({bool forceRefresh = false}) async {
    if (_cachedIsAdmin != null && !forceRefresh) return _cachedIsAdmin!;
    final client = Supabase.instance.client;
    final authUid = client.auth.currentUser?.id;
    if (authUid == null) {
      _cachedIsAdmin = false;
      return false;
    }
    try {
      final row = await client.from('profiles').select('is_admin').eq('auth_uid', authUid).maybeSingle();
      _cachedIsAdmin = (row?['is_admin'] as bool?) ?? false;
    } catch (_) {
      _cachedIsAdmin = false;
    }
    return _cachedIsAdmin!;
  }

  void invalidateCache() => _cachedIsAdmin = null;
}

/// Widget utilitaire : n'affiche [child] que si l'user courant est admin.
class AdminOnly extends StatelessWidget {
  final Widget child;
  const AdminOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdminService.instance.isCurrentUserAdmin(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return child;
      },
    );
  }
}
