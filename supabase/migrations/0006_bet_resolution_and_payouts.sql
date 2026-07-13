-- supabase/migrations/0006_bet_resolution_and_payouts.sql
-- Ferme la boucle argent : un admin tranche le résultat d'un bet, le
-- pool est réparti au prorata entre les gagnants (parimutuel), puis
-- l'admin règle chaque gagnant manuellement (virement Binance) et colle
-- le TxID de paiement pour traçabilité — même logique de confiance que
-- les dépôts : jamais de write direct côté client, tout passe par des
-- fonctions security definer / edge functions avec garde-fous admin.

alter table public.wagers
  add column if not exists payout_amount numeric(20,6),
  add column if not exists payout_status text not null default 'not_applicable'
    check (payout_status in ('not_applicable','owed','paid')),
  add column if not exists payout_tx_id text,
  add column if not exists paid_at timestamptz;

-- ---------- RÉSOLUTION D'UN BET (parimutuel) ----------
-- security definer + vérification is_admin() en interne : ne PEUT PAS
-- être appelée avec les droits d'un simple "authenticated" pour
-- contourner la policy, la vérification est dans la fonction elle-même.
create or replace function public.resolve_bet(p_bet_id text, p_winning_option text)
returns table (wager_id uuid, payout_amount numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_pool numeric(20,6);
  v_winner_pool numeric(20,6);
begin
  if not public.is_admin() then
    raise exception 'forbidden: admin only';
  end if;

  if not exists (select 1 from public.bets where id = p_bet_id and status = 'open') then
    raise exception 'bet not open or not found';
  end if;

  if not exists (
    select 1 from public.bets b, jsonb_array_elements_text(b.option_labels) opt
    where b.id = p_bet_id and opt = p_winning_option
  ) then
    raise exception 'winning_option not among bet option_labels';
  end if;

  select coalesce(sum(amount_unique), 0) into v_total_pool
    from public.wagers where bet_id = p_bet_id and status = 'confirmed';

  select coalesce(sum(amount_unique), 0) into v_winner_pool
    from public.wagers where bet_id = p_bet_id and status = 'confirmed' and chosen_option = p_winning_option;

  update public.bets
    set status = 'settled', winning_option = p_winning_option
    where id = p_bet_id;

  if v_winner_pool > 0 then
    update public.wagers w
      set payout_amount = round(w.amount_unique / v_winner_pool * v_total_pool, 6),
          payout_status = 'owed'
      where w.bet_id = p_bet_id and w.status = 'confirmed' and w.chosen_option = p_winning_option;
  end if;

  -- Les mises perdantes n'ont rien à recevoir (payout_status reste 'not_applicable').

  return query
    select w.id, w.payout_amount
    from public.wagers w
    where w.bet_id = p_bet_id and w.payout_status = 'owed';
end;
$$;

-- ---------- MARQUER UN PAYOUT COMME RÉGLÉ ----------
create or replace function public.mark_wager_paid(p_wager_id uuid, p_payout_tx_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden: admin only';
  end if;

  update public.wagers
    set payout_status = 'paid', payout_tx_id = p_payout_tx_id, paid_at = now()
    where id = p_wager_id and payout_status = 'owed';

  if not found then
    raise exception 'wager not found or not in owed state';
  end if;
end;
$$;

-- Ces deux fonctions sont appelées via RPC (supabase.rpc(...)) avec le
-- token de l'user connecté : la vérification is_admin() à l'intérieur
-- est la seule barrière, donc aucune policy RLS supplémentaire requise
-- sur les colonnes payout_*.
