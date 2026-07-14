-- supabase/migrations/0006_align_schema_to_repo.sql
-- Aligne le schéma distant sur les migrations du repo :
--   - Remplace wagers (hors migrations) par bet_stakes
--   - Répare les colonnes de bets (option_labels text[], status, creator_id)
--   - Supprime creator_public_key redondant

-- 1. Supprimer wagers et processed_deposits (pas dans les migrations)
drop table if exists public.processed_deposits cascade;
drop table if exists public.wagers cascade;

-- 2. Créer bet_stakes (migration 0005)
create table if not exists public.bet_stakes (
  id                    uuid primary key default gen_random_uuid(),
  bet_id                text not null references public.bets(id) on delete cascade,
  staker_id             text not null references public.profiles(public_key) on delete cascade,
  option_label          text not null,
  amount                numeric not null,
  amount_exact          numeric not null unique,
  status                text not null default 'pending_payment' check (status in ('pending_payment', 'confirmed', 'rejected')),
  tx_id                 text unique,
  created_at            timestamptz not null default now()
);

create index if not exists bet_stakes_bet_id_idx on public.bet_stakes (bet_id);
create index if not exists bet_stakes_staker_id_idx on public.bet_stakes (staker_id);
create index if not exists bet_stakes_amount_exact_idx on public.bet_stakes (amount_exact);
create index if not exists bet_stakes_tx_id_idx on public.bet_stakes (tx_id);

alter table public.bet_stakes enable row level security;

drop policy if exists "bet_stakes_select_all" on public.bet_stakes;
create policy "bet_stakes_select_all"
  on public.bet_stakes for select
  to authenticated
  using (true);

drop policy if exists "bet_stakes_insert_user" on public.bet_stakes;
create policy "bet_stakes_insert_user"
  on public.bet_stakes for insert
  to authenticated
  with check (staker_id = current_pubkey());

drop policy if exists "bet_stakes_update_user" on public.bet_stakes;
create policy "bet_stakes_update_user"
  on public.bet_stakes for update
  to authenticated
  using (staker_id = current_pubkey())
  with check (staker_id = current_pubkey());

-- 3. Recréer processed_deposits avec bet_stake_id
create table if not exists public.processed_deposits (
  tx_id                 text primary key,
  bet_stake_id          uuid not null references public.bet_stakes(id) on delete cascade,
  amount                numeric not null,
  processed_at          timestamptz not null default now()
);

alter table public.processed_deposits enable row level security;

drop policy if exists "processed_deposits_select_all" on public.processed_deposits;
create policy "processed_deposits_select_all"
  on public.processed_deposits for select
  to authenticated
  using (true);

-- 4. Réparer bets
drop policy if exists "bets_insert_admin_only" on public.bets;
drop policy if exists "bets_insert_all" on public.bets;
drop policy if exists "bets_update_admin_only" on public.bets;

alter table public.bets drop column if exists creator_public_key cascade;
alter table public.bets alter column creator_id set not null;
alter table public.bets alter column option_labels type text[] using option_labels::text::text[];
alter table public.bets alter column option_labels set not null;
alter table public.bets alter column description drop default;
alter table public.bets alter column category drop default;
alter table public.bets alter column min_stake drop default;

alter table public.bets drop constraint if exists bets_status_check;
alter table public.bets add constraint bets_status_check
  check (status in ('open', 'voting', 'settled', 'refunded'));

drop policy if exists "bets_select_all" on public.bets;
create policy "bets_select_all"
  on public.bets for select
  to authenticated
  using (true);

create policy "bets_insert_all"
  on public.bets for insert
  to authenticated
  with check (creator_id = current_pubkey());

-- UPDATE reste reservé aux admins
create policy "bets_update_admin"
  on public.bets for update
  to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.auth_uid = auth.uid() and p.is_admin = true
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.auth_uid = auth.uid() and p.is_admin = true
  ));

-- 5. Nettoyer les fonctions orphelines (wagers supprimée)
drop function if exists public.mark_wager_paid cascade;

-- 6. Publication Realtime
do $$
begin
  if not exists (
    select 1 from pg_publication_rel pr
    join pg_class c on pr.prrelid = c.oid
    join pg_publication p on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime' and c.relname = 'bet_stakes'
  ) then
    alter publication supabase_realtime add table public.bet_stakes;
  end if;

  if not exists (
    select 1 from pg_publication_rel pr
    join pg_class c on pr.prrelid = c.oid
    join pg_publication p on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime' and c.relname = 'processed_deposits'
  ) then
    alter publication supabase_realtime add table public.processed_deposits;
  end if;
end $$;
