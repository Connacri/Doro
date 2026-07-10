// lib/shared/widgets/supabase_unavailable_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/supabase/supabase_bootstrap.dart';

/// Écran affiché à la place du chat/profil tant que Supabase n'est pas
/// prêt — jamais un blocage de toute l'app : seuls les onglets qui en
/// dépendent affichent ceci, wallet/DAG restent utilisables.
class SupabaseUnavailableView extends StatelessWidget {
  const SupabaseUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    final bootstrap = context.watch<SupabaseBootstrap>();
    final initializing = bootstrap.status == SupabaseBootstrapStatus.initializing;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (initializing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text("Connexion à la messagerie…"),
            ] else ...[
              Icon(Icons.cloud_off, size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 16),
              Text(
                bootstrap.errorMessage ?? "Messagerie indisponible.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text("Réessayer"),
                onPressed: () => bootstrap.retry(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
