-- supabase/migrations/0006_allow_all_users_p2p_bets.sql
-- Permettre à tous les utilisateurs authentifiés de publier des paris P2P sur Supabase.

-- Supprimer l'ancienne politique restrictive aux administrateurs
drop policy if exists "bets_insert_admin" on public.bets;

-- Créer une nouvelle politique permettant à tout utilisateur authentifié d'insérer ses propres paris
create policy "bets_insert_all"
  on public.bets for insert
  to authenticated
  with check (
    creator_id = current_pubkey()
  );
